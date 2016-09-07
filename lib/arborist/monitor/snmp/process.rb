# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp' unless defined?( Arborist::Monitor::SNMP )

# SNMP running process checks.
#
class Arborist::Monitor::SNMP::Process
	include Arborist::Monitor::SNMP

	extend Loggability
	log_to :arborist

	# OIDS for discovering running processes.
	#
	PROCESS = {
		 list: '1.3.6.1.2.1.25.4.2.1.4',
		 args: '1.3.6.1.2.1.25.4.2.1.5'
	}

	# Global defaults for instances of this monitor
	#
	DEFAULT_OPTIONS = {
		processes: [] # list of procs to match
	}


	### This monitor is complex enough to require creating an instance from the caller.
	### Provide a friendlier error message the class was provided to exec() directly.
	###
	def self::run( nodes )
		return new.run( nodes )
	end


	### Create a new instance of this monitor.
	###
	def initialize( options=DEFAULT_OPTIONS )
		options = DEFAULT_OPTIONS.merge( options || {} )
		%i[ processes ].each do |opt|
			options[ opt ] = Array( options[opt] )
		end

		options.each do |name, value|
			self.public_send( "#{name.to_s}=", value )
		end
	end

	# Set an error if processes in this array aren't running.
	attr_accessor :processes


	### Perform the monitoring checks.
	###
	def run( nodes )
		super do |snmp, host|
			self.gather_processlist( snmp, host )
		end
	end


	#########
	protected
	#########

	### Collect running processes on +host+ from an existing (and open)
	#### +snmp+ connection.
	###
	def gather_processlist( snmp, host )
		self.log.debug "Getting running process list for %s" % [ host ]
		config = @identifiers[ host ].last || {}
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
			@results[ host ] = {}
		else
			@results[ host ] = { error: errors.join( ', ' ) }
		end
	end

end # class Arborist::Monitor::SNMP::Process

