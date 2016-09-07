# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp' unless defined?( Arborist::Monitor::SNMP )

# SNMP 5 minute load checks.
# Sets current 5 minute load as a 'load5' attribute.
#
class Arborist::Monitor::SNMP::Load
	include Arborist::Monitor::SNMP

	extend Loggability
	log_to :arborist

	# OIDS for discovering system load.
	#
	LOAD = {
		five_min: '1.3.6.1.4.1.2021.10.1.3.2'
	}

	# Global defaults for instances of this monitor
	#
	DEFAULT_OPTIONS = {
		error_at: 7
	}


	### Class #run creates a new instance.
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

	# Set an error if mount points are above this percentage.
	attr_accessor :error_at


	### Perform the monitoring checks.
	###
	def run( nodes )
		super do |snmp, host|
			self.gather_load( snmp, host )
		end
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

		config = @identifiers[ host ].last || {}
		error_at = config[ 'error_at' ] || self.error_at
		if load5 >= error_at
			@results[ host ] = {
				error: "Load has exceeded %0.2f over a 5 minute average" % [ error_at ],
				load5: load5
			}
		else
			@results[ host ] = { load5: load5 }
		end
	end

end # class Arborist::Monitor::SNMP::Load

