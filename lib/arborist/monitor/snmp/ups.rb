# -*- ruby -*-
# vim: set noet nosta sw=4 ts=4 :

require 'arborist/monitor/snmp' unless defined?( Arborist::Monitor::SNMP )

# Namespace for UPS check classes.
class Arborist::Monitor::SNMP::UPS
	include Arborist::Monitor::SNMP

end
