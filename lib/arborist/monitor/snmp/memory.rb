# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp' unless defined?( Arborist::Monitor::SNMP )

# SNMP memory availability checks.
# Returns total available memory in Kb to the 'available_memory' attribute.
#
class Arborist::Monitor::SNMP::Memory
	include Arborist::Monitor::SNMP

	extend Loggability
	log_to :arborist

	# OIDS for discovering memory usage.
	#
	MEMORY = {
		mem_avail: '1.3.6.1.4.1.2021.4.6.0'
	}

	# Global defaults for instances of this monitor
	#
	DEFAULT_OPTIONS = {
		error_at: 95, # in percent full
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
		options.each do |name, value|
			self.public_send( "#{name.to_s}=", value )
		end
	end

	# Set an error if memory used is below this many kilobytes.
	attr_accessor :error_at


	### Perform the monitoring checks.
	###
	def run( nodes )
		super do |snmp, host|
			self.gather_free_memory( snmp, host )
		end
	end


	#########
	protected
	#########

	### Collect available memory information for +host+ from an existing
	### (and open) +snmp+ connection.
	###
	def gather_free_memory( snmp, host )
		self.log.debug "Getting available memory for: %s" % [ host ]
		mem_avail = snmp.get( SNMP::ObjectId.new( MEMORY[:mem_avail] ) ).varbind_list.first.value.to_f
		self.log.debug "  Available memory on %s: %0.2f" % [ host, mem_avail ]

		config = @identifiers[ host ].last || {}
		error_at = config['error_at'] || self.error_at
		if mem_avail <= error_at
			@results[ host ] = {
				error: "Available memory is under %0.1fMB" % [ error_at.to_f / 1024 ],
				available_memory: mem_avail
			}
		else
			@results[ host ] = { available_memory: mem_avail }
		end
	end

end # class Arborist::Monitor::SNMP::Memory

