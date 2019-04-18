# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp/ups' unless defined?( Arborist::Monitor::SNMP::UPS )

# Checks for UPS battery health.
#
# Checks the available battery percentage, if the UPS is on battery,
# and the temperature of the battery.
#
class Arborist::Monitor::SNMP::UPS::Battery
	include Arborist::Monitor::SNMP

	extend Configurability, Loggability
	log_to :arborist_snmp

	# OIDS for discovering ups status.
	#
	OIDS = {
		battery_status:        '.1.3.6.1.2.1.33.1.2.1.0', # 1 - unk, 2 - normal, 3 - low, 4 - depleted
		seconds_on_battery:    '.1.3.6.1.2.1.33.1.2.2.0',
		est_minutes_remaining: '.1.3.6.1.2.1.33.1.2.3.0',
		est_charge_remaining:  '.1.3.6.1.2.1.33.1.2.4.0', # in percent
		battery_voltage:       '.1.3.6.1.2.1.33.1.2.5.0', # in 0.1v DC
		battery_current:       '.1.3.6.1.2.1.33.1.2.6.0', # in 0.1a DC
		battery_temperature:   '.1.3.6.1.2.1.33.1.2.7.0'  # in Celcius
	}

	# Human-readable translations for battery status OID.
	#
	BATTERY_STATUS = {
		1 => "Battery status is Unknown.",
		2 => "Battery is OK.",
		3 => "Battery is Low.",
		4 => "Battery is Depleted."
	}

	# Global defaults for instances of this monitor
	#
	configurability( 'arborist.snmp.ups.battery' ) do
		# What battery percentage qualifies as a warning
		setting :capacity_warn_at, default: 60

		# What battery temperature qualifies as a warning, in C
		setting :temperature_warn_at, default: 50
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
			self.check_battery( host, snmp )
		end
	end


	#########
	protected
	#########

	### Query SNMP and format information into a hash.
	###
	def format_battery( snmp )
		info = {}

		# basic info that's always available
		info[ :status ] = snmp.get( oid: OIDS[:battery_status] )
		info[ :capacity ] = snmp.get( oid: OIDS[:est_charge_remaining] )
		info[ :temperature ] = snmp.get( oid: OIDS[:battery_temperature] )
		info[ :minutes_remaining ]  = snmp.get( oid: OIDS[:est_minutes_remaining] )

		# don't report voltage if the UPS doesn't
		voltage = snmp.get( oid: OIDS[:battery_voltage] ) rescue nil
		info[ :voltage ] = voltage / 10 if voltage

		# don't report current if the UPS doesn't
		current = snmp.get( oid: OIDS[:battery_current] ) rescue nil
		info[ :current ] = current/10 if current

		# see if we are on battery
		info[ :seconds_on_battery ] = snmp.get( oid: OIDS[:seconds_on_battery] ) rescue 0
		info[ :in_use ] = ( info[ :seconds_on_battery ] != 0 )

		return { battery: info }
	end

	### Parse SNMP-provided information and alert based on thresholds.
	###
	def check_battery( host, snmp )
		info = self.format_battery( snmp )

		config    = identifiers[ host ].last || {}
		cap_warn  = config[ 'capacity_warn_at' ] || self.class.capacity_warn_at
		temp_warn = config[ 'temperature_warn_at' ] || self.class.temperature_warn_at

		in_use      = info.dig( :battery, :in_use )
		status      = info.dig( :battery, :status )
		capacity    = info.dig( :battery, :capacity )
		temperature = info.dig( :battery, :temperature )
		warnings	= []

		if in_use
			mins = info.dig( :battery, :minutes_remaining )
			warnings << "UPS on battery - %s minute(s) remaning." % [ mins ]
		end

		warnings << BATTERY_STATUS[ status ] if status != 2

		warnings << "Battery remaining capacity %0.1f%% less than %0.1f percent" %
			[ capacity, cap_warn ] if capacity <= cap_warn

		warnings << "Battery temperature %dC greater than %dC" %
			[ temperature, temp_warn ] if temperature >= temp_warn

		info[ :warning ] = warnings.join( "\n" ) unless warnings.empty?
		self.results[ host ] = info

	end

end # class Arborist::Monitor::UPS::Battery

