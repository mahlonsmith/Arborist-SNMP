# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp' unless defined?( Arborist::Monitor::SNMP )

# Disk capacity checks.
#
# Sets all configured mounts with their current usage percentage
# in an attribute named "mounts".
#
class Arborist::Monitor::SNMP::Disk
	include Arborist::Monitor::SNMP

	extend Configurability, Loggability
	log_to :arborist_snmp

	# OIDS required to pull disk information from net-snmp.
	#
	STORAGE_NET_SNMP = {
		path: '1.3.6.1.4.1.2021.9.1.2',
		percent: '1.3.6.1.4.1.2021.9.1.9',
		type: '1.3.6.1.2.1.25.3.8.1.4'
	}

	# The OID that matches a local windows hard disk.
	#
	WINDOWS_DEVICES = [
		'1.3.6.1.2.1.25.2.1.4', # local disk
		'1.3.6.1.2.1.25.2.1.7'  # removables, but we have to include them for iscsi mounts
	]

	# OIDS required to pull disk information from Windows.
	#
	STORAGE_WINDOWS = {
		type: '1.3.6.1.2.1.25.2.3.1.2',
		path: '1.3.6.1.2.1.25.2.3.1.3',
		total: '1.3.6.1.2.1.25.2.3.1.5',
		used: '1.3.6.1.2.1.25.2.3.1.6'
	}

	# The fallback warning capacity.
	WARN_AT = 90


	# Configurability API
	#
	configurability( 'arborist.snmp.disk' ) do
		# What percentage qualifies as a warning
		setting :warn_at, default: WARN_AT

		# If non-empty, only these paths are included in checks.
		#
		setting :include do |val|
			if val
				mounts = Array( val ).map{|m| Regexp.new(m) }
				Regexp.union( mounts )
			end
		end

		# Paths to exclude from checks
		#
		setting :exclude,
			default: [ '^/dev(/.+)?$', '/dev$', '^/net(/.+)?$', '/proc$', '^/run$', '^/sys/', '/sys$' ] do |val|
			mounts = Array( val ).map{|m| Regexp.new(m) }
			Regexp.union( mounts )
		end
	end


	### Return the properties used by this monitor.
	###
	def self::node_properties
		used_properties = USED_PROPERTIES.dup
		used_properties << :mounts
		return used_properties
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
			self.gather_disks( host, snmp )
		end
	end


	#########
	protected
	#########

	### Collect mount point usage for +host+ from an existing (and open)
	### +snmp+ connection.
	###
	def gather_disks( host, snmp )
		current_mounts = self.system =~ /windows\s+/i ? self.windows_disks( snmp ) : self.unix_disks( snmp )
		config         = self.identifiers[ host ].last['config'] || {}
		warn_at        = config[ 'warn_at' ] || self.class.warn_at

		self.log.warn self.identifiers[ host ]

		includes = self.format_mounts( config, 'include' ) || self.class.include
		excludes = self.format_mounts( config, 'exclude' ) || self.class.exclude

		current_mounts.reject! do |path, percentage|
			path = path.to_s
			excludes.match( path ) || ( includes && ! includes.match( path ) )
		end

		errors   = []
		warnings = []
		current_mounts.each_pair do |path, percentage|
			warn = if warn_at.is_a?( Hash )
				warn_at[ path ] || WARN_AT
			else
				warn_at
			end

			self.log.debug "%s:%s -> at %d, warn at %d" % [ host, path, percentage, warn ]

			if percentage >= warn.to_i
				if percentage >= 100
					errors << "%s at %d%% capacity" % [ path, percentage ]
				else
					warnings << "%s at %d%% capacity" % [ path, percentage ]
				end
			end
		end

		# Remove any past mounts that configuration exclusions should
		# now omit.
		mounts = self.identifiers[ host ].last[ 'mounts' ] || {}
		mounts.keys.each{|k| mounts[k] = nil }

		mounts.merge!( current_mounts )

		self.results[ host ] = { mounts: mounts }
		self.results[ host ][ :error ]   = errors.join(', ')   unless errors.empty?
		self.results[ host ][ :warning ] = warnings.join(', ') unless warnings.empty?
	end


	### Return a single regexp for the 'include' or 'exclude' section of
	### resource node's +config+, or nil if nonexistent.
	###
	def format_mounts( config, section )
		list = config[ section ] || return
		mounts = Array( list ).map{|m| Regexp.new(m) }
		return Regexp.union( mounts )
	end


	### Fetch information for Windows systems.
	###
	def windows_disks( snmp )
		oids = [
			STORAGE_WINDOWS[:path],
			STORAGE_WINDOWS[:type],
			STORAGE_WINDOWS[:total],
			STORAGE_WINDOWS[:used]
		]

		paths = snmp.walk( oid: oids[0] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end
		types = snmp.walk( oid: oids[1] ).each_with_object( [] ) do |(_, value), acc|
			acc << WINDOWS_DEVICES.include?( value )
		end
		totals = snmp.walk( oid: oids[2] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end
		used = snmp.walk( oid: oids[3] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end

		disks = {}
		paths.each_with_index do |path, idx|
			next if totals[ idx ].zero?
			next unless types[ idx ]
			disks[ path ] ||= {}
			disks[ path ] = (( used[idx].to_f / totals[idx] ) * 100).round( 1 )
		end

		return disks
	end


	### Fetch information for Unix/MacOS systems.
	###
	def unix_disks( snmp )
		oids = [ STORAGE_NET_SNMP[:path], STORAGE_NET_SNMP[:percent] ]
		paths = snmp.walk( oid: oids.first ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end
		capacities = snmp.walk( oid: oids.last ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end

		pairs = paths.zip( capacities )
		return Hash[ *pairs.flatten ]
	end

end # class Arborist::Monitor::SNMP::Disk

