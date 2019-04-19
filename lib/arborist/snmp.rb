# -*- ruby -*-
#encoding: utf-8

require 'loggability'
require 'arborist'


# Various monitoring checks using SNMP, for the Arborist monitoring toolkit.
module Arborist::SNMP
	extend Loggability

	# Loggability API -- set up a log host for this library
	log_as :arborist_snmp


	# Package version
	VERSION = '0.6.1'

	# Version control revision
	REVISION = %q$Revision$


	### Return the name of the library with the version, and optionally the build ID if
	### +include_build+ is true.
	def self::version_string( include_build: false )
		str = "%p v%s" % [ self, VERSION ]
		str << ' (' << REVISION.strip << ')' if include_build
		return str
	end


	require 'arborist/monitor/snmp'

end # module Arborist::SNMP

