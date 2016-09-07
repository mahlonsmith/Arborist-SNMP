# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp' unless defined?( Arborist::Monitor::SNMP )

# SNMP swap usage checks.
# Returns swap used in a 'swap_in_use' attribute.
#
class Arborist::Monitor::SNMP::Swap
	include Arborist::Monitor::SNMP

	extend Loggability
	log_to :arborist

	# Global defaults for instances of this monitor
	#
	DEFAULT_OPTIONS = {
		error_at: 95, # in percent full
	}

	# OIDS for discovering memory usage.
	#
	MEMORY = {
		swap_total: '1.3.6.1.4.1.2021.4.3.0',
		swap_avail: '1.3.6.1.4.1.2021.4.4.0',
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

	# Set an error if used swap exceeds this percentage.
	attr_accessor :error_at


	### Perform the monitoring checks.
	###
	def run( nodes )
		super do |snmp, host|
			self.gather_swap( snmp, host )
		end
	end


	#########
	protected
	#########

	### Collect used swap information for +host+ from an existing (and
	### open) +snmp+ connection.
	###
	def gather_swap( snmp, host )
		self.log.debug "Getting used swap for: %s" % [ host ]

		swap_total = snmp.get( SNMP::ObjectId.new(MEMORY[:swap_total]) ).varbind_list.first.value.to_f
		swap_avail = snmp.get( SNMP::ObjectId.new(MEMORY[:swap_avail]) ).varbind_list.first.value.to_f
		swap_in_use  = (( swap_avail.to_f / swap_total * 100 ) - 100 ).abs
		self.log.debug "  Swap in use on %s: %0.1f%%" % [ host, swap_in_use ]

		config = @identifiers[ host ].last || {}
		if swap_in_use >= ( config['error_at'] || self.error_at )
			@results[ host ] = {
				error: "%0.1f%% swap in use" % [ swap_in_use ],
				swap_in_use: swap_avail
			}
		else
			@results[ host ] = { swap_in_use: swap_in_use }
		end
	end

end # class Arborist::Monitor::SNMP::Swap

