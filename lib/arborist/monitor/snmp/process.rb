# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp' unless defined?( Arborist::Monitor::SNMP )

# SNMP running process checks.
#
# This only checks running userland processes.
#
class Arborist::Monitor::SNMP::Process
	include Arborist::Monitor::SNMP

	extend Configurability, Loggability
	log_to :arborist_snmp


	# OIDS for discovering running processes.
	# Of course, Windows does it slightly differently.
	#
	PROCESS = {
		netsnmp: {
			list: '1.3.6.1.2.1.25.4.2.1.4',
			args: '1.3.6.1.2.1.25.4.2.1.5'
		},
		windows: {
			list: '1.3.6.1.2.1.25.4.2.1.2',
			path: '1.3.6.1.2.1.25.4.2.1.4',
			args: '1.3.6.1.2.1.25.4.2.1.5'
		}
	}


	# Global defaults for instances of this monitor
	#
	configurability( 'arborist.snmp.processes' ) do
		# Default list of processes to check for
		setting :check, default: [] do |val|
			Array( val )
		end
	end


	### Return the properties used by this monitor.
	###
	def self::node_properties
		return USED_PROPERTIES
	end


	### Class #run creates a new instance and immediately runs it.
	###
	def self::run( nodes )
		return new.run( nodes )
	end


	### Perform the monitoring checks.
	###
	def run( nodes )
		super do |host, snmp|
			self.gather_processlist( host, snmp )
		end
	end


	#########
	protected
	#########

	### Collect running processes on +host+ from an existing (and open)
	#### +snmp+ connection.
	###
	def gather_processlist( host, snmp )
		config = self.identifiers[ host ].last || {}
		errors = []
		procs  = self.system =~ /windows\s+/i ? self.get_windows( snmp ) : self.get_procs( snmp )

		self.log.debug "Running processes for host: %s: %p" % [ host, procs ]
		self.results[ host ] = { count: procs.size }

		# Check against what is running.
		#
		Array( config['processes'] || self.class.check ).each do |process|
			process_r = Regexp.new( process )
			found = procs.find{|p| p.match(process_r) }
			errors << "'%s' is not running" % [ process ] unless found
		end

		self.results[ host ][ :error ] = errors.join( ', ' ) unless errors.empty?
	end


	### Parse OIDS and return an Array of running processes.
	### Windows specific behaviors.
	###
	def get_windows( snmp )
		oids = [ PROCESS[:windows][:path], PROCESS[:windows][:list], PROCESS[:windows][:args] ]
		return snmp.walk( oids ).each_slice( 3 ). each_with_object( [] ) do |vals, acc|
			path, process, args = vals[0][1], vals[1][1], vals[2][1]
			next if path.empty?

			process = "%s%s" % [ path, process ]
			process << " %s" % [ args ] unless args.empty?
			acc << process
		end
	end


	### Parse OIDS and return an Array of running processes.
	###
	def get_procs( snmp )
		oids = [ PROCESS[:netsnmp][:list], PROCESS[:netsnmp][:args] ]
		return snmp.walk( oids ).each_slice( 2 ).each_with_object( [] ) do |vals, acc|
			process, args = vals[0][1], vals[1][1]
			next if process.empty?

			process << " %s" % [ args ] unless args.empty?
			acc << process
		end
	end

end # class Arborist::Monitor::SNMP::Process

