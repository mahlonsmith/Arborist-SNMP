# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :
#encoding: utf-8

require 'arborist/monitor' unless defined?( Arborist::Monitor )
require 'net-snmp2'

# SNMP checks for Arborist.  Requires an SNMP agent to be installed
# on target machine, and the various "pieces" enabled for your platform.
#
# For example, for disk monitoring with Net-SNMP, you'll want to set
# 'includeAllDisks' in the snmpd.conf. bsnmpd on FreeBSD benefits from
# the 'bsnmp-ucd' package.  Etc.
#
module Arborist::Monitor::SNMP
	using Arborist::TimeRefinements
	extend Configurability, Loggability

	# Loggability API
	log_to :arborist_snmp

	# Always request the node addresses and any config.
	USED_PROPERTIES = [ :addresses, :config ].freeze

	# The OID that returns the system environment.
	IDENTIFICATION_OID = '1.3.6.1.2.1.1.1.0'

	# Global defaults for instances of this monitor
	#
	configurability( 'arborist.snmp' ) do
		setting :timeout, default: 2
		setting :retries, default: 1
		setting :community, default: 'public'
		setting :version, default: '2c'
		setting :port, default: 161

		# How many hosts to check simultaneously
		setting :batchsize, default: 25
	end

	# Indicate to FFI that we're using threads.
	Net::SNMP.thread_safe = true


	# The system type, as advertised.
	attr_reader :system

	# The mapping of addresses back to node identifiers.
	attr_reader :identifiers

	# The results hash that is sent back to the manager.
	attr_reader :results


	### Connect to the SNMP daemon and yield.
	###
	def run( nodes )

		# Create mapping of addresses back to node identifiers,
		# and retain any custom (overrides) config per node.
		#
		@identifiers = {}
		@results     = {}
		nodes.each_pair do |(identifier, props)|
			next unless props.key?( 'addresses' )
			address = props[ 'addresses' ].first
			self.identifiers[ address ] = [ identifier, props['config'] ]
		end

		# Perform the work!
		#
		mainstart  = Time.now
		threads    = ThreadGroup.new
		batchcount = nodes.size / Arborist::Monitor::SNMP.batchsize
		self.log.debug "Starting SNMP run for %d nodes" % [ nodes.size ]

		self.identifiers.keys.each_slice( Arborist::Monitor::SNMP.batchsize ).each_with_index do |slice, batch|
			slicestart = Time.now
			self.log.debug "  %d hosts (batch %d of %d)" % [
				slice.size,
				batch + 1,
				batchcount + 1
			]

			slice.each do |host|
				thr = Thread.new do
					config = self.identifiers[ host ].last || {}
					opts = {
						peername:  host,
						port:      config[ 'port' ]      || Arborist::Monitor::SNMP.port,
						version:   config[ 'version' ]   || Arborist::Monitor::SNMP.version,
						community: config[ 'community' ] || Arborist::Monitor::SNMP.community,
						timeout:   config[ 'timeout' ]   || Arborist::Monitor::SNMP.timeout,
						retries:   config[ 'retries' ]   || Arborist::Monitor::SNMP.retries
					}

					snmp = Net::SNMP::Session.open( opts )
					begin
						@system = snmp.get( IDENTIFICATION_OID ).varbinds.first.value
						yield( host, snmp )

					rescue Net::SNMP::TimeoutError, Net::SNMP::Error => err
						self.log.error "%s: %s %s" % [ host, err.message, snmp.error_message ]
						self.results[ host ] = {
							error: "%s" % [ snmp.error_message ]
						}
					rescue => err
						self.results[ host ] = {
							error: "Uncaught exception. (%s: %s)" % [ err.class.name, err.message ]
						}
					ensure
						snmp.close
					end
				end

				threads.add( thr )
			end

			# Wait for thread completions
			threads.list.map( &:join )
			self.log.debug "  finished after %0.1f seconds." % [ Time.now - slicestart ]
		end
		self.log.debug "Completed SNMP run for %d nodes after %0.1f seconds." % [ nodes.size, Time.now - mainstart ]

		# Map everything back to identifier -> attribute(s), and send to the manager.
		#
		reply = self.results.each_with_object({}) do |(address, results), hash|
			identifier = self.identifiers[ address ] or next
			hash[ identifier.first ] = results
		end
		return reply

	ensure
		@identifiers = {}
		@results     = {}
	end

end # Arborist::Monitor::SNMP

require 'arborist/monitor/snmp/cpu'
require 'arborist/monitor/snmp/disk'
require 'arborist/monitor/snmp/process'
require 'arborist/monitor/snmp/memory'

