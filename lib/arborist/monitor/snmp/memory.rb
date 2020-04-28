# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp' unless defined?( Arborist::Monitor::SNMP )

# SNMP memory and swap utilization checks.
#
# Set 'usage' and 'available' keys as properties, in percentage/GBs,
# respectively.
#
# By default, doesn't warn on memory usage, only swap, since
# that's more indicitive of a problem.  You can still set the
# 'physical_warn_at' key to force warnings on ram usage, for embedded
# systems or other similar things without virtual memory.
#
class Arborist::Monitor::SNMP::Memory
	include Arborist::Monitor::SNMP

	extend Configurability, Loggability
	log_to :arborist_snmp

	# OIDS for discovering memory usage.
	#
	MEMORY = {
		total:  '1.3.6.1.4.1.2021.4.5.0',
		avail: '1.3.6.1.4.1.2021.4.6.0',
		windows: {
			label: '1.3.6.1.2.1.25.2.3.1.3',
			units: '1.3.6.1.2.1.25.2.3.1.4',
			total: '1.3.6.1.2.1.25.2.3.1.5',
			used:  '1.3.6.1.2.1.25.2.3.1.6'
		}
	}

	# OIDS for discovering swap usage.
	#
	SWAP = {
		total: '1.3.6.1.4.1.2021.4.3.0',
		avail: '1.3.6.1.4.1.2021.4.4.0'
	}

	# Global defaults for instances of this monitor
	#
	configurability( 'arborist.snmp.memory' ) do
		# What memory usage percentage qualifies as a warning
		setting :physical_warn_at, default: nil

		# What swap usage percentage qualifies as a warning
		setting :swap_warn_at, default: 60
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
			self.gather_memory( host, snmp )
		end
	end


	#########
	protected
	#########

	### Collect available memory information for +host+ from an existing
	### (and open) +snmp+ connection.
	###
	def gather_memory( host, snmp )
		info = self.system =~ /windows\s+/i ? self.get_windows( snmp ) : self.get_mem( snmp )

		config           = self.identifiers[ host ].last['config'] || {}
		physical_warn_at = config[ 'physical_warn_at' ] || self.class.physical_warn_at
		swap_warn_at     = config[ 'swap_warn_at' ] || self.class.swap_warn_at

		self.log.debug "Memory data on %s: %p" % [ host, info ]
		memory, swap = info[:memory], info[:swap]
		self.results[ host ] = { memory: memory, swap: swap }

		memusage = memory[ :usage ].to_i
		if physical_warn_at && memusage >= physical_warn_at
			self.results[ host ][ :warning ] = "%0.1f memory utilization exceeds %0.1f percent" % [
				memusage,
				physical_warn_at
			]
		end

		swapusage = swap[ :usage ].to_i
		if swapusage >= swap_warn_at
			self.results[ host ][ :warning ] = "%0.1f swap utilization exceeds %0.1f percent" % [
				swapusage,
				swap_warn_at
			]
		end
	end


	### Return a hash of usage percentage in use, and free mem in
	### megs.
	###
	def get_mem( snmp )
		info  = {}
		info[ :memory ] = self.calc_memory( snmp, MEMORY )
		info[ :swap ]   = self.calc_memory( snmp, SWAP )

		return info
	end


	### Windows appends virtual and physical memory onto the last two items
	### of the storage iterator, because that made sense in someone's mind.
	### Walk the whole oid tree, and get the values we're after, return
	### a hash of usage percentage in use and free mem in megs.
	###
	def get_windows( snmp )
		info  = { memory: {}, swap: {} }
		mem_idx, swap_idx = nil

		snmp.walk( oid: MEMORY[:windows][:label] ).each_with_index do |(_, val), i|
			mem_idx  = i + 1 if val =~ /physical memory/i
			swap_idx = i + 1 if val =~ /virtual memory/i
		end
		return info unless mem_idx

		info[ :memory ] = self.calc_windows_memory( snmp, mem_idx )
		info[ :swap ]   = self.calc_windows_memory( snmp, swap_idx )

		return info
	end


	### Format usage and available amount, given an OID hash.
	###
	def calc_memory( snmp, oids )
		info = { usage: 0, available: 0 }
		avail = snmp.get( oid: oids[:avail] ).to_f
		total = snmp.get( oid: oids[:total] ).to_f
		used  = total - avail

		return info if avail.zero?

		info[ :usage ]     = (( used / total ) * 100 ).round( 2 )
		info[ :available ] = (( total - used ) / 1024 ).round( 2 )
		return info
	end


	### Format usage and available amount for windows.
	###
	def calc_windows_memory( snmp, idx)
		info = { usage: 0, available: 0 }
		return info unless idx

		units = snmp.get( oid: MEMORY[:windows][:units] + ".#{idx}" )
		total = snmp.get( oid: MEMORY[:windows][:total] + ".#{idx}" ).to_f * units
		used  = snmp.get( oid: MEMORY[:windows][:used] + ".#{idx}" ).to_f * units

		info[ :usage ]     = (( used / total ) * 100 ).round( 2 )
		info[ :available ] = (( total - used ) / 1024 / 1024 ).round( 2 )
		return info
	end


end # class Arborist::Monitor::SNMP::Memory

