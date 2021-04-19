# Example script sets up a simple topology 
# and sets up Queue monitors for wireless
# devices.
#
# Two-hop topology:  2	1	0
#
# Jun 2010
#
#

Mac/802_11 set RTSThreshold_ 3000
Mac/802_11 set dataRate_ 1e6
Mac/802_11 set CWMin_ 31
Mac/802_11 set CWMax_ 1023

#Agent/DSDV set fulltcp_ 1					;# DSDV issues with FullTCP. 
										;# www.cs.odu.edu/~mweigle/research/netsim/fulltcp-wlan.html
										;# For RG, comment out line 49 in godagent.cc

# ====================================================================== 
# Define options 
# ====================================================================== 
set val(chan)         	Channel/WirelessChannel  	;# channel type 
set val(prop)         	Propagation/TwoRayGround 	;# radio-propagation model 
set val(ant)        	Antenna/OmniAntenna      		;# Antenna type 
set val(ll)           	LL                       			;# Link layer type 
set val(ifq)          	Queue/DropTail/PriQueue  	;# Interface queue type 
set val(ifqlen)       	20       	          			;# max packet in ifq 
set val(netif)        	Phy/WirelessPhy          		;# network interface type 
set val(mac)          	Mac/802_11               		;# MAC type 
set val(rp)           	DSDV                     			;# ad-hoc routing protocol  
set val(nn)           	3                        			;# number of mobilenodes 

# ======================================================================
# Main Program
# ======================================================================
#
# Initialize Global Variables
#
# Create simulator
set ns_		[new Simulator]

# Set up trace file
set tracefd     [open simple.tr w]
$ns_ use-newtrace
$ns_ trace-all $tracefd
set cwfd [open CWnd.tr w]
set rttfd [open RTTime.tr w]
set qfd [open Qmon.tr w]

# set up topography object
set topo       [new Topography]
$topo load_flatgrid 2000 2000

# Procedure for plotting TCP cong. window
proc plotCW  agent {
    global ns_ cwfd 
    upvar $agent agt_
    set time 0.1
    set now [$ns_ now]
    puts -nonewline $cwfd [format "%4.4f" $now]
    
    # 'array size' command returns the number of elements in an array
    for {set i 0} {$i < [array size agt_]} {incr i} {
         set cwnd [$agt_($i) set cwnd_]  
         puts -nonewline $cwfd  [format "\t%.1f" $cwnd]
    }
    puts $cwfd " "
    $ns_ at [expr $now+$time] "plotCW $agent"
}

# Procedure for plotting TCP SRTT
proc plotRTT agent {
    global ns_ rttfd 
    upvar $agent agt_
    set time 0.1
    set now [$ns_ now]
    puts -nonewline $rttfd [format "%4.4f" $now]
    
    # 'array size' command returns the number of elements in an array
    for {set i 0} {$i < [array size agt_]} {incr i} {
         set srttval [$agt_($i) set srtt_]  
         puts -nonewline $rttfd  [format "\t%.1f" $srttval]
    }
    puts $rttfd " "
    $ns_ at [expr $now+$time] "plotRTT $agent"
}

# Procedure for monitoring Q size
proc plotQSize qmonitor {
    global ns_ qfd
    upvar $qmonitor qmon_
    set time 0.1
    set now [$ns_ now]
    puts -nonewline $qfd [format "%4.4f" $now]
    
    for {set i 0} {$i < [array size qmon_]} {incr i} {
         set len [$qmon_($i) set pkts_]
	 set drps [$qmon_($i) set pdrops_]
         puts -nonewline $qfd  "\t $len\t $drps"
    }
   puts $qfd " "
    $ns_ at [expr $now+$time] "plotQSize $qmonitor"
}

proc stop {} {
    global ns_ tracefd
    $ns_ flush-trace
    close $tracefd
    $ns_ halt
}

#
# Create God
#
create-god $val(nn)

#
#  Create the specified number of mobilenodes [$val(nn)] and "attach" them
#  to the channel. 

# configure node
$ns_ node-config -adhocRouting $val(rp) \
			 -llType $val(ll) \
			 -macType $val(mac) \
			 -ifqType $val(ifq) \
			 -ifqLen $val(ifqlen) \
			 -antType $val(ant) \
			 -propType $val(prop) \
			 -phyType $val(netif) \
			 -channel [new $val(chan)] \
			 -topoInstance $topo \
			 -agentTrace ON \
			 -routerTrace OFF \
			 -macTrace OFF \
			 -movementTrace OFF			

# Create nodes			 
for {set i 0} {$i < $val(nn) } {incr i} {
	set node_($i) [$ns_ node]	
	$node_($i) random-motion 0		;# disable random motion
}

# Set node positions
$node_(0) set X_ 0.0
$node_(0) set Y_ 0.0
$node_(0) set Z_ 0.0
$node_(1) set X_ 200.0
$node_(1) set Y_ 0.0
$node_(1) set Z_ 0.0
$node_(2) set X_ 400.0
$node_(2) set Y_ 0.0
$node_(2) set Z_ 0.0

# Setup traffic flow between nodes
# 1500 - 20 byte IP header - 20 byte TCP header = 1460 bytes
Application/FTP set packetSize_ 1460 	;# This size EXCLUDES the TCP header

# Set up TCP agents
for {set i 0} {$i < $val(nn)-1} {incr i} {
	set agt [new Agent/TCP/Newreno]
	$agt set class_ 1
	set agt_($i) $agt
	set app [new Application/FTP]
	set app_($i) $app
	set sink [new Agent/TCPSink]
	set sink_($i) $sink
	$ns_ attach-agent $node_([expr $i + 1]) $agt
	$ns_ attach-agent $node_(0) $sink
	$ns_ connect $agt $sink
	$app attach-agent $agt	
	$agt set fid_ [expr $i + 1]		;# 1-1 mapping between flowid and source
}

# Set up Queue monitoring objects
for {set i 0} {$i < $val(nn)} {incr i} {
	set monitor_($i) [$ns_ monitor-ifq $node_($i) stdout]
}

# Fire away the agents!
for { set i 0 } { $i < $val(nn)-1 } { incr i } {
    set randomint [expr 10 + [expr (int(rand()*5))]]
    puts "Activating flowid $i at time $randomint"
    $ns_ at $randomint "$app_($i) start"
} 

# Enable monitoring characteristics
$ns_ at 10.0 "plotCW agt_"
$ns_ at 10.0 "plotRTT agt_"
$ns_ at 10.0 "plotQSize monitor_"

set file [open cwnd_rtt.tr w]
$agt_(0) attach $file
$ns_ at 10.0 "$agt_(0) trace cwnd_"
$ns_ at 10.0 "$agt_(0) trace rtt_"

$ns_ at 250.0 "stop"
puts "Starting Simulation..."
$ns_ run
