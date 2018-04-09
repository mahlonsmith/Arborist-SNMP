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

		paths = snmp.walk( oid: oids[0] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end
		procs = snmp.walk( oid: oids[1] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end
		args = snmp.walk( oid: oids[2] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end

		return paths.zip( procs, args ).collect do |(path, process, arg)|
			next unless path && process
			next if path.empty?
			path << process unless process.empty?
			path << " %s" % [ arg.to_s ] if arg && ! arg.empty?
			path
		end.compact
	end


	### Parse OIDS and return an Array of running processes.
	###
	def get_procs( snmp )
		oids = [ PROCESS[:netsnmp][:list], PROCESS[:netsnmp][:args] ]

		procs = snmp.walk( oid: oids.first ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end
		args = snmp.walk( oid: oids.last ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end

		return procs.zip( args ).collect do |(process, arg)|
			next if process.empty?
			process << " %s" % [ arg.to_s ] unless arg.empty?
			process
		end.compact
	end

end # class Arborist::Monitor::SNMP::Process

