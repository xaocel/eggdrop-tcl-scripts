#--------------------------------------------------------
#               ssh.tcl by xaoc @undernet
#        nc + SOCKS + colors + flood protection
#        Could be used in connection with warp-cli xD
#--------------------------------------------------------

set cmdchar "!"
set ssh_flood_time 10    ;# seconds per nick
array set ssh_lastuse {}

# IRC colors
set ssh_color_accepted 03 ;# green
set ssh_color_refused 04  ;# red
set ssh_color_timeout 07  ;# orange
set ssh_color_host 10      ;# teal

# SOCKS proxy
set ssh_socks "127.0.0.1:1081"

bind pub - ${cmdchar}ssh ssh_cmd

# ---------------- flood protection ----------------
proc ssh_cmd {nick uhost hand chan text} {
    global ssh_lastuse ssh_flood_time ssh_socks

    set now [clock seconds]
    if {[info exists ssh_lastuse($nick)] && ($now - $ssh_lastuse($nick)) < $ssh_flood_time} {
        putquick "PRIVMSG $chan :\00304$nick\003 please wait before using !ssh again."
        return
    }
    set ssh_lastuse($nick) $now

    if {$text eq ""} {
        putquick "PRIVMSG $chan :\00304Usage:\003 !ssh <host/ip> <port>"
        return
    }

    set args [split $text " "]
    set host [lindex $args 0]
    set port [lindex $args 1]

    if {$port eq ""} {
        putquick "PRIVMSG $chan :\00304Usage:\003 !ssh <host/ip> <port>"
        return
    }

    putquick "PRIVMSG $chan :Checking $host:$port..."
    after 10 [list ssh_run $chan $host $port $ssh_socks]
}

# ---------------- async port check ----------------
proc ssh_run {chan host port socks} {
    # Compose nc command with SOCKS proxy
    set cmd [list nc -x $socks -z -v -w 5 $host $port]

    # Run command capturing stdout + stderr
    set rc [catch {exec {*}$cmd 2>@1} output]

    # Normalize output
    set text [string tolower $output]

    # Determine status using real nc outputs
    if {[string match "*succeeded*" $text]} {
        set status "accepted"
        set color 03
    } elseif {[string match "*connection failed*connection refused*" $text]} {
        set status "refused"
        set color 04
    } elseif {[string match "*broken pipe*" $text] || [string match "*host unreachable*" $text]} {
        set status "timeout or ip/host doesn't exist"
        set color 07
    } else {
        set status "timeout"
        set color 07
    }

    # IRC-colored output
    putquick "PRIVMSG $chan :\00310$host\003:\003$color$port\003 -> \003$color$status\003"
}
