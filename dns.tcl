#--------------------------------------------------------
#                Simple !DNS (IPv4 + IPv6) by xaoc
#                + flood protection per nick
#--------------------------------------------------------

package require http
package require json
package require tls
http::register https 443 ::tls::socket

set cmdchar "!"
set dns_flood_time 10    ;# seconds between uses per nick
array set dns_lastuse {}

bind pub - ${cmdchar}dns dns:cmd

# ---------------- DoH hostname lookup ----------------
proc doh_lookup {host} {
    set ips {}

    # --- A record ---
    set url "https://cloudflare-dns.com/dns-query?name=$host&type=A"
    set token [http::geturl $url -headers {"accept" "application/dns-json"} -timeout 10000]
    if {[http::status $token] eq "ok"} {
        set data [http::data $token]
        http::cleanup $token
        if {![catch {set json [json::json2dict $data]}]} {
            if {[dict exists $json Answer]} {
                foreach ans [dict get $json Answer] {
                    if {[dict get $ans type] == 1} { lappend ips [dict get $ans data] }
                }
            }
        }
    }

    # --- AAAA record ---
    set url "https://cloudflare-dns.com/dns-query?name=$host&type=AAAA"
    set token [http::geturl $url -headers {"accept" "application/dns-json"} -timeout 10000]
    if {[http::status $token] eq "ok"} {
        set data [http::data $token]
        http::cleanup $token
        if {![catch {set json [json::json2dict $data]}]} {
            if {[dict exists $json Answer]} {
                foreach ans [dict get $json Answer] {
                    if {[dict get $ans type] == 28} { lappend ips [dict get $ans data] }
                }
            }
        }
    }

    return $ips
}

# ---------------- command ----------------
proc dns:cmd {nick uhost hand chan text} {
    global dns_lastuse dns_flood_time

    # ===== FLOOD PROTECTION =====
    set now [clock seconds]
    if {[info exists dns_lastuse($nick)]} {
        if {($now - $dns_lastuse($nick)) < $dns_flood_time} {
            putquick "PRIVMSG $chan :\00304$nick\003 please wait before using !dns again."
            return
        }
    }
    set dns_lastuse($nick) $now

    if {$text eq ""} {
        putquick "PRIVMSG $chan :\00304Usage:\003 !dns <host or ip>"
        return
    }

    # IPv4
    if {[regexp {^([0-9]{1,3}\.){3}[0-9]{1,3}$} $text]} {
        dnslookup $text dns:reverse $chan $text
        return
    }

    # IPv6
    if {[regexp {:} $text]} {
        dnslookup $text dns:reverse $chan $text
        return
    }

    # Hostname lookup (A + AAAA) via DoH
    set ips [doh_lookup $text]

    if {[llength $ips] == 0} {
        putquick "PRIVMSG $chan :\00304Unable to resolve\003 $text"
        return
    }

    set ips [lrange $ips 0 9]   ;# max 10 results
#    set out [join $ips " | "]
set sep "\00314 | \00307"
set out [join $ips $sep]

    # Colored output: 03=green, 07=orange
    putquick "PRIVMSG $chan :\00303$text\003 -> \00307$out\003"
}

# ---------------- reverse lookup ----------------
proc dns:reverse {ip host status chan target} {

    if {!$status} {
        putquick "PRIVMSG $chan :\00304Unable to resolve\003 $target"
        return
    }

    # Colored output: 10=teal, 03=green
    putquick "PRIVMSG $chan :\00310$target\003 -> \00303$host\003"
}

putlog "Simple DNS script loaded (fully patched: DoH hostname + IPv4/IPv6 PTR + colored output + flood protection)"
