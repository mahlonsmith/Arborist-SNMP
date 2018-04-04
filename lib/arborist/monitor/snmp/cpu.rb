# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp' unless defined?( Arborist::Monitor::SNMP )

# Machine load/cpu checks.
#
# Sets current 1, 5, and 15 minute loads under the 'load' attribute,
# and calculates/warns on cpu overutilization.
#
class Arborist::Monitor::SNMP::CPU
	include Arborist::Monitor::SNMP

	extend Configurability, Loggability
	log_to :arborist_snmp

	# OIDS for discovering system load.
	#
	OIDS = {
		load: '1.3.6.1.4.1.2021.10.1.3',
		cpu:  '1.3.6.1.2.1.25.3.3.1.2'
	}

	# When walking load OIDS, the iterator count matches
	# these labels.
	#
	LOADKEYS = {
		1 => :load1,
		2 => :load5,
		3 => :load15
	}


	# Global defaults for instances of this monitor
	#
	configurability( 'arborist.snmp.cpu' ) do
		# What overutilization percentage qualifies as a warning
		setting :warn_at, default: 80
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
			self.find_load( host, snmp )
		end
	end


	#########
	protected
	#########

	### Return system CPU data.
	###
	def cpu( snmp )
		return snmp.walk( OIDS[:cpu] )
	end


	### Find load data, add additional niceties for reporting.
	###
	def format_load( snmp )
		info = { cpu: {}, load: {} }
		cpus = self.cpu( snmp )

		info[ :cpu ][ :count ] = cpus.size

		# Windows SNMP doesn't have a concept of "load" over time,
		# so we have to just use the current averaged CPU usage.
		#
		# This means that windows machines will very likely want to
		# adjust the default "overutilization" number, considering
		# it's really just how much of the CPU is used at the time of
		# the monitor run, along with liberal use of the Observer "only
		# alert after X events" pragmas.
		#
		if self.system =~ /windows\s+/i
			info[ :cpu ][ :usage ] = cpus.values.inject( :+ ).to_f / cpus.size
			info[ :message ] = "System is %0.1f%% in use." % [ info[ :cpu ][ :usage ] ]

		# UCDavis stuff is better for alerting only after there has been
		# an extended load event.  Use the 5 minute average to avoid
		# state changes on transient spikes.
		#
		else
			snmp.walk( OIDS[:load] ).each_with_index do |(_, value), idx|
				next unless LOADKEYS[ idx + 1 ]
				info[ :load ][ LOADKEYS[idx + 1] ] = value.to_f
			end

			percentage = (( ( info[:load][ :load5 ] / cpus.size ) - 1 ) * 100 ).round( 1 )

			if percentage < 0
				info[ :message ] = "System is %0.1f%% idle." % [ percentage.abs ]
				info[ :cpu ][ :usage ] = percentage + 100
			else
				info[ :message ] = "System is %0.1f%% overloaded." % [ percentage ]
				info[ :cpu ][ :usage ] = percentage
			end
		end

		return info
	end


	### Collect the load information for +host+ from an existing
	### (and open) +snmp+ connection.
	###
	def find_load( host, snmp )
		info = self.format_load( snmp )

		config  = identifiers[ host ].last || {}
		warn_at = config[ 'warn_at' ] || self.class.warn_at
		usage   = info.dig( :cpu, :usage ) || 0

		if usage >= warn_at
			info[ :warning ] = "%0.1f utilization exceeds %0.1f percent" % [ usage, warn_at ]
		end

		self.results[ host ] = info
	end

end # class Arborist::Monitor::SNMP::CPU

