# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :
#encoding: utf-8
#
# SNMP checks for Arborist.  Requires an SNMP agent to be installed
# on target machine, and the various "pieces" enabled.  For your platform.
#
# For example, for disk monitoring with Net-SNMP, you'll want to set
# 'includeAllDisks' in the snmpd.conf. bsnmpd on FreeBSD benefits from
# the 'bsnmp-ucd' package.  Etc.
#

require 'loggability'
require 'arborist/monitor' unless defined?( Arborist::Monitor )
require 'snmp'

using Arborist::TimeRefinements

# Shared SNMP monitor logic.
#
module Arborist::Monitor::SNMP
	extend Loggability
	log_to :arborist

	# The version of this library.
	VERSION = '0.3.0'

	# Global defaults for instances of this monitor
	#
	DEFAULT_OPTIONS = {
		timeout:   2,
		retries:   1,
		community: 'public',
		port:      161
	}


	### Connect to the SNMP daemon and yield.
	###
	def run( nodes )
		self.log.debug "Got nodes to SNMP check: %p" % [ nodes ]
		opts = Arborist::Monitor::SNMP::DEFAULT_OPTIONS

		# Create mapping of addresses back to node identifiers,
		# and retain any custom (overrides) config per node.
		#
		@identifiers = {}
		@results     = {}

		nodes.each_pair do |(identifier, props)|
			next unless props.key?( 'addresses' )
			address = props[ 'addresses' ].first
			@identifiers[ address ] = [ identifier, props['config'] ]
		end

		# Perform the work!
		#
		threads = []
		@identifiers.keys.each do |host|
			thr = Thread.new do
				Thread.current.abort_on_exception = true

				config = @identifiers[host].last || {}
				opts = {
					host:      host,
					port:      config[ 'port' ]      || opts[ :port ],
					community: config[ 'community' ] || opts[ :community ],
					timeout:   config[ 'timeout' ]   || opts[ :timeout ],
					retries:   config[ 'retries' ]   || opts[ :retries ]
				}

				begin
					SNMP::Manager.open( opts ) do |snmp|
						yield( snmp, host )
					end
				rescue SNMP::RequestTimeout
					@results[ host ] = {
						error: "Host is not responding to SNMP requests."
					}
				rescue StandardError => err
					@results[ host ] = {
						error: "Network is not accessible. (%s: %s)" % [ err.class.name, err.message ]
					}
				end
			end
			threads << thr
		end

		# Wait for thread completion
		threads.map( &:join )

		# Map everything back to identifier -> attribute(s), and send to the manager.
		#
		reply = @results.each_with_object({}) do |(address, results), hash|
			identifier = @identifiers[ address ] or next
			hash[ identifier.first ] = results
		end
		self.log.debug "Sending to manager: %p" % [ reply ]
		return reply

	ensure
		@identifiers = {}
		@results     = {}
	end

end # Arborist::Monitor::SNMP

require 'arborist/monitor/snmp/disk'
require 'arborist/monitor/snmp/load'
require 'arborist/monitor/snmp/memory'
require 'arborist/monitor/snmp/process'
require 'arborist/monitor/snmp/swap'

