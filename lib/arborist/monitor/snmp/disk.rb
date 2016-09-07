# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp' unless defined?( Arborist::Monitor::SNMP )

# SNMP Disk capacity checks.
# Returns all mounts with their current usage percentage in a "mount" attribute.
#
class Arborist::Monitor::SNMP::Disk
	include Arborist::Monitor::SNMP

	extend Loggability
	log_to :arborist

	# The OID that returns the system environment.
	IDENTIFICATION_OID = '1.3.6.1.2.1.1.1.0'

	# For net-snmp systems, ignore mount types that match
	# this regular expression.  This includes null/union mounts
	# and NFS, currently.
	STORAGE_IGNORE = %r{25.3.9.(?:2|14)$}

	# The OID that matches a local windows hard disk.  Anything else
	# is a remote (SMB) mount.
	WINDOWS_DEVICE = '1.3.6.1.2.1.25.2.1.4'

	# OIDS required to pull disk information from net-snmp.
	#
	STORAGE_NET_SNMP = [
		'1.3.6.1.4.1.2021.9.1.2', # paths
		'1.3.6.1.2.1.25.3.8.1.4', # types
		'1.3.6.1.4.1.2021.9.1.9'  # percents
	]

	# OIDS required to pull disk information from Windows.
	#
	STORAGE_WINDOWS = [
		'1.3.6.1.2.1.25.2.3.1.2', # types
		'1.3.6.1.2.1.25.2.3.1.3', # paths
		'1.3.6.1.2.1.25.2.3.1.5', # totalsize
		'1.3.6.1.2.1.25.2.3.1.6'  # usedsize
	]

	# Global defaults for instances of this monitor
	#
	DEFAULT_OPTIONS = {
		error_at: 95, # in percent full
		include:  [], # if non-empty, only these paths are included in checks
		exclude:  []  # paths to exclude from checks
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
		%i[ include exclude ].each do |opt|
			options[ opt ] = Array( options[opt] )
		end

		options.each do |name, value|
			self.public_send( "#{name.to_s}=", value )
		end
	end

	# Set an error if mount points are above this percentage.
	attr_accessor :error_at

	# Only check these specific mount points.
	attr_accessor :include

	# Exclude these mount points (array of paths) from checks.
	attr_accessor :exclude


	### Perform the monitoring checks.
	###
	def run( nodes )
		super do |snmp, host|
			self.gather_disks( snmp, host )
		end
	end


	#########
	protected
	#########

	### Collect mount point usage for +host+ from an existing (and open)
	#### +snmp+ connection.
	###
	def gather_disks( snmp, host )
		self.log.debug "Getting disk information for %s" % [ host ]
		errors  = []
		results = {}
		mounts  = self.get_disk_percentages( snmp )
		config  = @identifiers[ host ].last || {}

		includes = config[ 'include' ] || self.include
		excludes = config[ 'exclude' ] || self.exclude

		mounts.each_pair do |path, percentage|
			next if excludes.include?( path )
			next if ! includes.empty? && ! includes.include?( path )
			if percentage >= ( config[ 'error_at' ] || self.error_at )
				errors << "%s at %d%% capacity" % [ path, percentage ]
			end
		end

		results[ :mounts ] = mounts
		results[ :error ] = errors.join( ', ' ) unless errors.empty?

		@results[ host ] = results
	end


	### Given a SNMP object, return a hash of:
	###
	###    device path => percentage full
	###
	def get_disk_percentages( snmp )

		# Does this look like a windows system, or a net-snmp based one?
		system_type = snmp.get( SNMP::ObjectId.new( IDENTIFICATION_OID ) ).varbind_list.first.value
		disks = {}

		# Windows has it's own MIBs.
		#
		if system_type =~ /windows/i
			snmp.walk( STORAGE_WINDOWS ) do |list|
				next unless list[0].value.to_s == WINDOWS_DEVICE
				disks[ list[1].value.to_s ] = ( list[3].value.to_f / list[2].value.to_f ) * 100
			end
			return disks
		end

		# Everything else.
		#
		snmp.walk( STORAGE_NET_SNMP ) do |list|
			mount = list[0].value.to_s
			next if mount == 'noSuchInstance'

			next if list[2].value.to_s == 'noSuchInstance'
			used = list[2].value.to_i

			unless list[1].value.to_s == 'noSuchInstance'
				typeoid = list[1].value.join('.').to_s
				next if typeoid =~ STORAGE_IGNORE
			end
			next if mount =~ /\/(?:dev|proc)$/

			disks[ mount ] = used
		end

		return disks
	end

end # class Arborist::Monitor::SNMP::Disk

