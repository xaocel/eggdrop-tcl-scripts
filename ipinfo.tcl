# ipinfo.tcl by xaoc @undernet
# !ip <nick|IP>
# IPv4 + IPv6, RDNS, flood protection, colored output

package require http

# ===== SETTINGS =====
set ipinfo_flood_time 10     ;# seconds per user
set ipinfo_timeout 10000     ;# HTTP timeout (ms)

array set ipinfo_lastuse {}
array set ipinfo_pending {}   ;# nick -> channel

# ===== BINDINGS =====
bind pub - "!ip" ipinfo_cmd
bind raw - 340 ipinfo_userip

# ===== PUB COMMAND =====
proc ipinfo_cmd {nick host hand chan text} {
    global ipinfo_lastuse ipinfo_flood_time ipinfo_timeout ipinfo_pending

    set arg [string trim [lindex $text 0]]
    if {$arg eq ""} {
        putserv "PRIVMSG $chan :\00307Usage:\003 !ip <nick or IP>"
        return
    }

    # Flood protection
    set now [clock seconds]
    if {[info exists ipinfo_lastuse($nick)] && ($now - $ipinfo_lastuse($nick) < $ipinfo_flood_time)} {
        putserv "PRIVMSG $chan :\00304$nick\003 please wait before using !ip again."
        return
    }
    set ipinfo_lastuse($nick) $now

    # ===== CHECK IF ARG IS AN IP =====
    if {[regexp {^(\d{1,3}\.){3}\d{1,3}$} $arg] || [regexp {^[0-9a-fA-F:]+$} $arg]} {
        # looks like IPv4 or IPv6
        ipinfo_lookup $chan $arg
    } else {
        # assume it's a nick
        set arg_l [string tolower $arg]
        set ipinfo_pending($arg_l) $chan
        putserv "USERIP $arg"
    }
}

# ===== RAW USERIP HANDLER =====
proc ipinfo_userip {from keyword args} {
    global ipinfo_pending

    # Join args and extract after colon
    set raw [join $args " "]
    if {![regexp {:(.+)} $raw -> payload]} { return }

    # Parse nick and IP
    if {![regexp {([^=]+)=.[^@]+@(.+)} $payload -> nick ip]} { return }

    # Skip fake Undernet hostnames
    if {[string match "*.users.undernet.org" $ip]} {
        set nick_l [string tolower $nick]
        if {[info exists ipinfo_pending($nick_l)]} {
            set chan $ipinfo_pending($nick_l)
            unset ipinfo_pending($nick_l)
            putserv "PRIVMSG $chan :\00304$nick\003 has a non-resolvable host ($ip)."
        }
        return
    }

    set nick_l [string tolower $nick]
    if {![info exists ipinfo_pending($nick_l)]} { return }

    set chan $ipinfo_pending($nick_l)
    unset ipinfo_pending($nick_l)

    ipinfo_lookup $chan $ip
}

# ===== IPINFO LOOKUP =====
proc ipinfo_lookup {chan ip} {
    global ipinfo_timeout

    # URL encode
    set encoded_ip [http::formatQuery ip $ip]
    set encoded_ip [string range $encoded_ip 3 end]

    set url "http://ip-api.com/json/$encoded_ip?fields=status,message,country,regionName,city,isp,org,as,query,reverse"

    set token [http::geturl $url -timeout $ipinfo_timeout]
    if {[http::status $token] ne "ok"} {
        putserv "PRIVMSG $chan :\00304API connection error.\003"
        http::cleanup $token
        return
    }

    set data [http::data $token]
    http::cleanup $token

    if {[string match "*\"status\":\"fail\"*" $data]} {
        regexp {\"message\":\"([^\"]+)\"} $data -> message
        putserv "PRIVMSG $chan :\00304Lookup failed:\003 $message"
        return
    }

    # Extract fields
    regexp {\"country\":\"([^\"]*)\"} $data -> country
    regexp {\"regionName\":\"([^\"]*)\"} $data -> region
    regexp {\"city\":\"([^\"]*)\"} $data -> city
    regexp {\"isp\":\"([^\"]*)\"} $data -> isp
    regexp {\"org\":\"([^\"]*)\"} $data -> org
    regexp {\"as\":\"([^\"]*)\"} $data -> asn
    regexp {\"query\":\"([^\"]*)\"} $data -> query
    regexp {\"reverse\":\"([^\"]*)\"} $data -> rdns

    if {$rdns eq ""} { set rdns "N/A" }

    # Colored output
    putserv "PRIVMSG $chan :\00303IP:\003 $query \00310|\003 \00307$country, $region, $city\003 \00310|\003 ISP: $isp \00310|\003 ASN: $asn \00310|\003 RDNS: $rdns"
}
