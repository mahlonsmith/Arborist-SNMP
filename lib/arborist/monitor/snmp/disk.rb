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
		path:    '1.3.6.1.4.1.2021.9.1.2',
		percent: '1.3.6.1.4.1.2021.9.1.9',
		type:    '1.3.6.1.2.1.25.3.8.1.4',
		access:  '1.3.6.1.2.1.25.3.8.1.5'
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
		type:  '1.3.6.1.2.1.25.2.3.1.2',
		path:  '1.3.6.1.2.1.25.2.3.1.3',
		total: '1.3.6.1.2.1.25.2.3.1.5',
		used:  '1.3.6.1.2.1.25.2.3.1.6'
	}

	# The fallback warning capacity.
	WARN_AT = 90

	# Don't alert if a mount is readonly by default.
	ALERT_READONLY = false

	# Access mode meanings
	ACCESS_READWRITE = 1
	ACCESS_READONLY  = 2

	# Configurability API
	#
	configurability( 'arborist.snmp.disk' ) do
		# What percentage qualifies as a warning
		setting :warn_at, default: WARN_AT

		# Set down if the mounts are readonly?
		setting :alert_readonly, default: ALERT_READONLY

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
		alert_readonly = config[ 'alert_readonly' ] || self.class.alert_readonly

		self.log.debug self.identifiers[ host ]

		includes = self.format_mounts( config, 'include' ) || self.class.include
		excludes = self.format_mounts( config, 'exclude' ) || self.class.exclude

		current_mounts.reject! do |path, data|
			path = path.to_s
			excludes.match( path ) || ( includes && ! includes.match( path ) )
		end

		errors   = []
		warnings = []
		current_mounts.each_pair do |path, data|
			warn = if warn_at.is_a?( Hash )
				warn_at[ path ] || self.class.warn_at
			else
				warn_at
			end

			readonly = alert_readonly.is_a?( Hash ) ? alert_readonly[ path ] : alert_readonly

			self.log.debug "%s:%s -> %p, warn at %d" % [ host, path, data, warn ]

			if data[ :capacity ] >= warn.to_i
				if data[ :capacity ] >= 100
					errors << "%s at %d%% capacity" % [ path, data[ :capacity ] ]
				else
					warnings << "%s at %d%% capacity" % [ path, data[ :capacity ] ]
				end
			end

			if readonly && data[ :accessmode ] == ACCESS_READONLY
				errors << "%s is mounted read-only." % [ path ]
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
		paths = snmp.walk( oid: STORAGE_WINDOWS[:path] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end
		types = snmp.walk( oid: STORAGE_WINDOWS[:type] ).each_with_object( [] ) do |(_, value), acc|
			acc << WINDOWS_DEVICES.include?( value )
		end
		totals = snmp.walk( oid: STORAGE_WINDOWS[:total] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end
		used = snmp.walk( oid: STORAGE_WINDOWS[:used] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end

		disks = {}
		paths.each_with_index do |path, idx|
			next if totals[ idx ].zero?
			next unless types[ idx ]
			disks[ path ] ||= {}
			disks[ path ][ :capacity ] = (( used[idx].to_f / totals[idx] ) * 100).round( 1 )
		end

		return disks
	end


	### Fetch information for Unix/MacOS systems.
	###
	def unix_disks( snmp )
		paths = snmp.walk( oid: STORAGE_NET_SNMP[:path] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end
		capacities = snmp.walk( oid: STORAGE_NET_SNMP[:percent] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end
		accessmodes = snmp.walk( oid: STORAGE_NET_SNMP[:access] ).each_with_object( [] ) do |(_, value), acc|
			acc << value
		end

		pairs = paths.each_with_object( {} ).with_index do |(p, acc), idx|
			acc[p] = { capacity: capacities[idx], accessmode: accessmodes[idx] }
		end
		return pairs
	end

end # class Arborist::Monitor::SNMP::Disk

