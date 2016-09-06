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

# SNMP specific monitors and monitor logic.
#
class Arborist::Monitor::SNMP
	extend Loggability
	log_to :arborist

	# The version of this library.
	VERSION = '0.2.1'

	# "Modes" that this monitor understands.
	VALID_MODES = %i[ disk load memory swap process ]

	# The OID that returns the system environment.
	IDENTIFICATION_OID = '1.3.6.1.2.1.1.1.0'

	# For net-snmp systems, ignore mount types that match
	# this regular expression.  This includes null/union mounts
	# and NFS, currently.
	STORAGE_IGNORE = %r{25.3.9.(?:2|14)$}

	# The OID that matches a local windows hard disk.  Anything else
	# is a remote (SMB) mount.
	WINDOWS_DEVICE = '1.3.6.1.2.1.25.2.1.4'

	# OIDS required to pull disk information from net-snmp.
	#
	STORAGE_NET_SNMP = [
		'1.3.6.1.4.1.2021.9.1.2', # paths
		'1.3.6.1.2.1.25.3.8.1.4', # types
		'1.3.6.1.4.1.2021.9.1.9'  # percents
	]

	# OIDS required to pull disk information from Windows.
	#
	STORAGE_WINDOWS = [
		'1.3.6.1.2.1.25.2.3.1.2', # types
		'1.3.6.1.2.1.25.2.3.1.3', # paths
		'1.3.6.1.2.1.25.2.3.1.5', # totalsize
		'1.3.6.1.2.1.25.2.3.1.6'  # usedsize
	]

	# OIDS for discovering memory usage.
	#
	MEMORY = {
		swap_total: '1.3.6.1.4.1.2021.4.3.0',
		swap_avail: '1.3.6.1.4.1.2021.4.4.0',
		mem_avail:  '1.3.6.1.4.1.2021.4.6.0'
	}

	# OIDS for discovering system load.
	#
	LOAD = {
		five_min: '1.3.6.1.4.1.2021.10.1.3.2'
	}

	# OIDS for discovering running processes.
	#
	PROCESS = {
		 list: '1.3.6.1.2.1.25.4.2.1.4',
		 args: '1.3.6.1.2.1.25.4.2.1.5'
	}


	# Global defaults for instances of this monitor
	#
	DEFAULT_OPTIONS = {
		timeout:          2,
		retries:          1,
		community:        'public',
		port:             161,
		storage_error_at: 95,    # in percent full
		storage_include:  [],    # if non-empty, only these paths are included in checks
		storage_exclude:  [],    # paths to exclude from checks
		load_error_at:    7,
		swap_error_at:    25,    # in percent remaining
		mem_error_at:     51200, # in kilobytes
		processes:        []     # list of procs to match
	}


	### This monitor is complex enough to require creating an instance from the caller.
	### Provide a friendlier error message the class was provided to exec() directly.
	###
	def self::run( nodes )
		self.log.error "Please use %s via an instance." % [ self.name ]
		return {}
	end


	### Create a new instance of this monitor.
	###
	def initialize( options=DEFAULT_OPTIONS )
		options = DEFAULT_OPTIONS.merge( options || {} )
		%i[ storage_include storage_exclude processes ].each do |opt|
			options[ opt ] = Array( options[opt] )
		end

		options.each do |name, value|
			self.public_send( "#{name.to_s}=", value )
		end
	end


	# The mode (section) that this SMMP instance should check.
	# Must be a +VALID_MODES+ mode.
	attr_reader :mode

	# Mapping of node addresses back to the node identifier.
	attr_reader :identifiers

	# The results from the SNMP daemons, keyed by address.
	attr_reader :results

	# A timeout in seconds if the SNMP server isn't responding.
	attr_accessor :timeout

	# Retry with the timeout this many times.  Defaults to 1.
	attr_accessor :retries

	# The SNMP UDP port, if running on non default.
	attr_accessor :port

	# The community string to connect with.
	attr_accessor :community

	# Set an error if mount points are above this percentage.
	attr_accessor :storage_error_at

	# Only check these specific mount points.
	attr_accessor :storage_include

	# Exclude these mount points (array of paths) from checks.
	attr_accessor :storage_exclude

	# Set an error if the 5 minute load average exceeds this.
	attr_accessor :load_error_at

	# Set an error if used swap exceeds this percentage.
	attr_accessor :swap_error_at

	# Set an error if memory used is below this many kilobytes.
	attr_accessor :mem_error_at

	# Set an error if processes in this array aren't running.
	attr_accessor :processes


	### Set the SNMP mode, after validation.
	###
	def mode=( mode )
		unless VALID_MODES.include?( mode.to_sym )
			self.log.error "Unknown SNMP mode: %s" % [ mode ]
			return nil
		end

		@mode    = mode.to_sym
		@results = {}
	end


	### Perform the monitoring checks.
	###
	def run( nodes )
		self.log.debug "Got nodes to SNMP check: %p" % [ nodes ]

		# Sanity check.
		#
		unless self.mode
			self.log.error "You must set the 'mode' for the SNMP monitor. (%s)" % [ VALID_MODES.join( ', ' ) ]
			return {}
		end

		# Create mapping of addresses back to node identifiers,
		# and retain any custom configs per node.
		#
		@identifiers = {}
		nodes.each_pair do |(identifier, props)|
			next unless props.key?( 'addresses' )
			address = props[ 'addresses' ].first
			self.identifiers[ address ] = [ identifier, props['config'] ]
		end

		# Perform the work!
		#
		threads = []
		self.identifiers.keys.each do |host|
			thr = Thread.new do
				Thread.current.abort_on_exception = true

				config = self.identifiers[host].last || {}
				opts = {
					host:      host,
					port:      config[ 'port' ] || self.port,
					community: config[ 'community' ] || self.community,
					timeout:   config[ 'timeout' ] || self.timeout,
					retries:   config[ 'retries' ] || self.retries
				}

				begin
					SNMP::Manager.open( opts ) do |snmp|
						case self.mode
						when :disk
							self.gather_disks( snmp, host )
						when :load
							self.gather_load( snmp, host )
						when :memory
							self.gather_free_memory( snmp, host )
						when :swap
							self.gather_swap( snmp, host )
						when :process
							self.gather_processlist( snmp, host )
						end
					end
				rescue SNMP::RequestTimeout
					self.results[ host ] = {
						error: "Host is not responding to SNMP requests."
					}
				rescue StandardError => err
					self.results[ host ] = {
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
		reply = self.results.each_with_object({}) do |(address, results), hash|
			identifier = self.identifiers[ address ] or next
			hash[ identifier.first ] = results
		end
		self.log.debug "Sending to manager: %p" % [ reply ]
		return reply
	end


	#########
	protected
	#########

	### Collect the load information for +host+ from an existing
	### (and open) +snmp+ connection.
	###
	def gather_load( snmp, host )
		self.log.debug "Getting system load for: %s" % [ host ]
		load5 = snmp.get( SNMP::ObjectId.new( LOAD[:five_min] ) ).varbind_list.first.value.to_f
		self.log.debug "  Load on %s: %0.2f" % [ host, load5 ]

		config = self.identifiers[ host ].last || {}
		error_at = config[ 'load_error_at' ] || self.load_error_at
		if load5 >= error_at
			self.results[ host ] = {
				error: "Load has exceeded %0.2f over a 5 minute average" % [ error_at ],
				load5: load5
			}
		else
			self.results[ host ] = { load5: load5 }
		end
	end


	### Collect available memory information for +host+ from an existing
	### (and open) +snmp+ connection.
	###
	def gather_free_memory( snmp, host )
		self.log.debug "Getting available memory for: %s" % [ host ]
		mem_avail = snmp.get( SNMP::ObjectId.new( MEMORY[:mem_avail] ) ).varbind_list.first.value.to_f
		self.log.debug "  Available memory on %s: %0.2f" % [ host, mem_avail ]

		config = self.identifiers[ host ].last || {}
		error_at = config['mem_error_at'] || self.mem_error_at
		if mem_avail <= error_at
			self.results[ host ] = {
				error: "Available memory is under %0.1fMB" % [ error_at.to_f / 1024 ],
				available_memory: mem_avail
			}
		else
			self.results[ host ] = { available_memory: mem_avail }
		end
	end


	### Collect used swap information for +host+ from an existing (and
	### open) +snmp+ connection.
	###
	def gather_swap( snmp, host )
		self.log.debug "Getting used swap for: %s" % [ host ]

		swap_total = snmp.get( SNMP::ObjectId.new(MEMORY[:swap_total]) ).varbind_list.first.value.to_f
		swap_avail = snmp.get( SNMP::ObjectId.new(MEMORY[:swap_avail]) ).varbind_list.first.value.to_f
		swap_used  = ( "%0.2f" % ((swap_avail / swap_total.to_f * 100 ) - 100).abs ).to_f
		self.log.debug "  Swap in use on %s: %0.2f" % [ host, swap_used ]

		config = self.identifiers[ host ].last || {}
		if swap_used >= ( config['swap_error_at'] || self.swap_error_at )
			self.results[ host ] = {
				error: "%0.2f%% swap in use" % [ swap_used ],
				swap_used: swap_used
			}
		else
			self.results[ host ] = { swap_used: swap_used }
		end
	end


	### Collect mount point usage for +host+ from an existing (and open)
	#### +snmp+ connection.
	###
	def gather_disks( snmp, host )
		self.log.debug "Getting disk information for %s" % [ host ]
		errors  = []
		results = {}
		mounts  = self.get_disk_percentages( snmp )
		config  = self.identifiers[ host ].last || {}

		includes = config[ 'storage_include' ] || self.storage_include
		excludes = config[ 'storage_exclude' ] || self.storage_exclude

		mounts.each_pair do |path, percentage|
			next if excludes.include?( path )
			next if ! includes.empty? && ! includes.include?( path )
			if percentage >= ( config[ 'storage_error_at' ] || self.storage_error_at )
				errors << "%s at %d%% capacity" % [ path, percentage ]
			end
		end

		results[ :mounts ] = mounts
		results[ :error ] = errors.join( ', ' ) unless errors.empty?

		self.results[ host ] = results
	end


	### Collect running processes on +host+ from an existing (and open)
	#### +snmp+ connection.
	###
	def gather_processlist( snmp, host )
		self.log.debug "Getting running process list for %s" % [ host ]
		config = self.identifiers[ host ].last || {}
		procs  = []
		errors = []

		snmp.walk([ PROCESS[:list], PROCESS[:args] ]) do |list|
			process = list[0].value.to_s
			args    = list[1].value.to_s
			procs << "%s %s " % [ process, args ]
		end

		# Check against the running stuff, setting an error if
		# one isn't found.
		#
		Array( config['processes'] || self.processes ).each do |process|
			process_r = Regexp.new( process )
			found = procs.find{|p| p.match(process_r) }
			errors << "Process '%s' is not running" % [ process, host ] unless found
		end

		self.log.debug "  %d running processes" % [ procs.length ]
		if errors.empty?
			self.results[ host ] = {}
		else
			self.results[ host ] = { error: errors.join( ', ' ) }
		end
	end


	### Given a SNMP object, return a hash of:
	###
	###    device path => percentage full
	###
	def get_disk_percentages( snmp )

		# Does this look like a windows system, or a net-snmp based one?
		system_type = snmp.get( SNMP::ObjectId.new( IDENTIFICATION_OID ) ).varbind_list.first.value
		disks = {}

		# Windows has it's own MIBs.
		#
		if system_type =~ /windows/i
			snmp.walk( STORAGE_WINDOWS ) do |list|
				next unless list[0].value.to_s == WINDOWS_DEVICE
				disks[ list[1].value.to_s ] = ( list[3].value.to_f / list[2].value.to_f ) * 100
			end
			return disks
		end

		# Everything else.
		#
		snmp.walk( STORAGE_NET_SNMP ) do |list|
			mount = list[0].value.to_s
			next if mount == 'noSuchInstance'

			next if list[2].value.to_s == 'noSuchInstance'
			used = list[2].value.to_i

			unless list[1].value.to_s == 'noSuchInstance'
				typeoid = list[1].value.join('.').to_s
				next if typeoid =~ STORAGE_IGNORE
			end
			next if mount =~ /\/(?:dev|proc)$/

			disks[ mount ] = used
		end

		return disks
	end
end # class Arborist::Monitor::SNMP

