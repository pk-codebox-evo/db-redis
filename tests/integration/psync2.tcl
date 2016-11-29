start_server {tags {"wait"}} {
start_server {} {
start_server {} {
start_server {} {
start_server {} {
    for {set j 0} {$j < 5} {incr j} {
        set R($j) [srv [expr 0-$j] client]
        set R_host($j) [srv [expr 0-$j] host]
        set R_port($j) [srv [expr 0-$j] port]
        puts "Log file: [srv [expr 0-$j] stdout]"
    }

    set master_id 0                 ; # Current master
    set start_time [clock seconds]  ; # Test start time
    set counter_value 0             ; # Current value of the Redis counter "x"

    # Config
    set duration 60                 ; # Total test seconds

    set genload 1                   ; # Load master with writes at every cycle

    set genload_time 5000           ; # Writes duration time in ms

    set disconnect 1                ; # Break replication link between random
                                      # master and slave instances while the
                                      # master is loaded with writes.

    set disconnect_period 1000      ; # Disconnect repl link every N ms.

    while {([clock seconds]-$start_time) < $duration} {

        # Create a random replication layout.
        # Start with switching master (this simulates a failover).

        # 1) Select the new master.
        set master_id [randomInt 5]
        set used [list $master_id]
        test "PSYNC2: \[NEW LAYOUT\] Set #$master_id as master" {
            $R($master_id) slaveof no one
            if {$counter_value == 0} {
                $R($master_id) set x $counter_value
            }
        }

        # 2) Attach all the slaves to a random instance
        while {[llength $used] != 5} {
            while 1 {
                set slave_id [randomInt 5]
                if {[lsearch -exact $used $slave_id] == -1} break
            }
            set rand [randomInt [llength $used]]
            set mid [lindex $used $rand]
            set master_host $R_host($mid)
            set master_port $R_port($mid)

            test "PSYNC2: Set #$slave_id to replicate from #$mid" {
                $R($slave_id) slaveof $master_host $master_port
            }
            lappend used $slave_id
        }

        # 3) Increment the counter and wait for all the instances
        # to converge.
        test "PSYNC2: cluster is consistent after failover" {
            $R($master_id) incr x; incr counter_value
            for {set j 0} {$j < 5} {incr j} {
                wait_for_condition 50 1000 {
                    [$R($j) get x] == $counter_value
                } else {
                    fail "Instance #$j x variable is inconsistent"
                }
            }
        }

        # 4) Generate load while breaking the connection of random
        # slave-master pairs.
        test "PSYNC2: generate load while killing replication links" {
            set t [clock milliseconds]
            set next_break [expr {$t+$disconnect_period}]
            while {[clock milliseconds]-$t < $genload_time} {
                if {$genload} {
                    $R($master_id) incr x; incr counter_value
                }
                if {[clock milliseconds] == $next_break} {
                    set next_break \
                        [expr {[clock milliseconds]+$disconnect_period}]
                    set slave_id [randomInt 5]
                    if {$disconnect} {
                        $R($slave_id) client kill type master
                        puts "+++ Breaking link for slave #$slave_id"
                    }
                }
            }
        }

        # 5) Increment the counter and wait for all the instances
        set x [$R($master_id) get x]
        test "PSYNC2: cluster is consistent after load (x = $x)" {
            for {set j 0} {$j < 5} {incr j} {
                wait_for_condition 50 1000 {
                    [$R($j) get x] == $counter_value
                } else {
                    fail "Instance #$j x variable is inconsistent"
                }
            }
        }

        # Put down the old master so that it cannot generate more
        # replication stream, this way in the next master switch, the time at
        # which we move slaves away is not important, each will have full
        # history (otherwise PINGs will make certain slaves have more history),
        # and sometimes a full resync will be needed.
        $R($master_id) slaveof 127.0.0.1 0 ;# We use port zero to make it fail.

        for {set j 0} {$j < 5} {incr j} {
            puts "$j: sync_full: [status $R($j) sync_full]"
            puts "$j: id1      : [status $R($j) master_replid]:[status $R($j) master_repl_offset]"
            puts "$j: id2      : [status $R($j) master_replid2]:[status $R($j) second_repl_offset]"
            puts "$j: backlog  : firstbyte=[status $R($j) repl_backlog_first_byte_offset] len=[status $R($j) repl_backlog_histlen]"
            puts "---"
        }
    }

# XXXXXXXXXXXX
    while 1 { puts -nonewline .; flush stdout; after 1000}
# XXXXXXXXXXXX

}}}}}
