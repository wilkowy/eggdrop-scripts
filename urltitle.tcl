# Name		Display URL Title
# Author	wilk wilkowy
# Version	1.4 (2018..2018-02-19)
# License	GNU GPL v2 or any later version

# Users having this flags are ignored.
set urltitle_ignored "I|I"

# Users having this flags can trigger script.
set urltitle_allowed "-|-"

# Limit title length (0 - off).
set urltitle_max_length 0

# Protect against floods, in seconds (0 - off).
set urltitle_antiflood 10

# This is how script introduces itself to servers, chosen randomly.
set urltitle_agent [list "Mozilla/5.0 (X11; Linux x86_64; rv:57.0) Gecko/20100101 Firefox/57.0"]

# Website fetching timeout, in miliseconds.
set urltitle_timeout 5000

# Max depth for 301/302 redirections.
set urltitle_max_depth 5

# On/off .chanset flag.
setudef flag urltitle

bind pubm $urltitle_allowed {*://*} urltitle:fetch

package require http
if {![catch {set urltitle_tlsver [package require tls]}]} {
	set urltitle_tls 1
	if {[package vcompare $urltitle_tlsver 1.6.4] < 0} {
		putlog "URL Title: tls package version <1.6.4 = no SNI support, some HTTPS links will not work properly"
	}
} else {
	set urltitle_tls 0
	putlog "URL Title: no tls package = no SSL/TLS support (HTTPS protocol)"
}
if {![catch {package require htmlparse}]} {
	set urltitle_htmlparse 1
} else {
	set urltitle_htmlparse 0
	putlog "URL Title: no htmlparse package = no escape sequences substitution"
}

proc urltitle:tlssocket {args} {
	global urltitle_tlsver
	set opts [lrange $args 0 end-2]
	set host [lindex $args end-1]
	set port [lindex $args end]
	if {[package vcompare $urltitle_tlsver 1.7.11] >= 0} {
		::tls::socket -tls1 1 -tls1.1 1 -tls1.2 1 -ssl3 0 -ssl2 0 -autoservername 1 {*}$opts $host $port
	} elseif {[package vcompare $urltitle_tlsver 1.6.4] >= 0} {
		::tls::socket -tls1 1 -tls1.1 1 -tls1.2 1 -ssl3 0 -ssl2 0 -servername $host {*}$opts $host $port
	} else {
		::tls::socket -tls1 1 -ssl3 0 -ssl2 0 {*}$opts $host $port
	}
}

proc urltitle:gethtml {query depth {referer ""} {cookies ""}} {
	global urltitle_tls urltitle_agent urltitle_timeout urltitle_state
	if {[string length $query] == 0 || $depth < 0} { return "" }
	if {$urltitle_tls && [string match -nocase "https://*" $query]} {
		::http::register https 443 urltitle:tlssocket
	}
	#-accept "text/html"
	::http::config -useragent [lindex $urltitle_agent [rand [llength $urltitle_agent]]]
	if {[llength $cookies] > 0} {
		catch { set http [::http::geturl $query -timeout $urltitle_timeout -headers [list "Referer" $referer "Cookie" [string trim [join $cookies ";"] ";"]]] } httperror
	} else {
		catch { set http [::http::geturl $query -timeout $urltitle_timeout] } httperror
	}
	if {![info exists http]} {
		putlog "URL Title: connection error for $query ($httperror)"
		return ""
	}
	set status [::http::status $http]
	set code [::http::ncode $http]
	set html ""
	if {$status eq "ok"} {
		upvar #0 $http state
		array set urltitle_state [array get state]
		if {$code in [list 301 302 303 307]} {
			set redir ""
			set cook [list]
			foreach {name value} $state(meta) {
				if {[string equal -nocase "Location" $name]} {
					set redir $value
				} elseif {[string equal -nocase "Set-Cookie" $name]} {
					lappend cook [lindex [split $value ";"] 0]
				}
			}
			if {[llength $cook] == 0 && [llength $cookies] != 0} {
				set cook $cookies
			}
			if {$redir ne ""} {
				::http::cleanup $http
				if {$urltitle_tls} {
					#::http::unregister https
				}
				set addr ""
				if {[regexp -nocase {^https?://[^/&?]+?} $query addr] && ![regexp -nocase {^https?://} $redir]} {
					#array set parts [uri::split $query]
					#set redir "$parts(scheme)://$parts(host)$redir"
					set redir "$addr$redir"
				}
				#tailcall?
				return [urltitle:gethtml $redir [expr {$depth - 1}] $addr $cook]
			}
		}
		if {[string match -nocase "text/html*" $state(type)]} {
			set html [::http::data $http]
		} else {
			putlog "URL Title: invalid content-type for $query ($state(type))"
		}
	} else {
		putlog "URL Title: connection failed for $query ($status)"
	}
	::http::cleanup $http
	if {$urltitle_tls} {
		#::http::unregister https
	}
	return $html
}

proc urltitle:recode {title} {
	global urltitle_state
	set charset_m [set charset_b [set charset ""]]
	if {[regexp -nocase {<meta[^>]+?charset="?([^"]+?)"} $urltitle_state(body) match charset]} { ;#"
		set charset_m [::http::CharsetToEncoding $urltitle_state(charset)]
		set charset_b [::http::CharsetToEncoding $charset]
	}
	if {![string equal -nocase $charset_m $charset_b] && $charset_b ne "" && $charset_b ne "binary"} {
		set title [encoding convertfrom $charset_b $title]
	}
	return $title
}

proc urltitle:gettitle {query} {
	global urltitle_htmlparse urltitle_max_depth 
	set html [string map {"\r" "" "\n" ""} [urltitle:gethtml $query $urltitle_max_depth]]
	set title ""
	if {![regexp -nocase {<title[^>]*?>([^<>]*?)</title>} $html match title]} { return "" }
	if {[string match -nocase "*youtube.com/*" $query] || [string match -nocase "*youtu.be/*" $query]} {
		set yttitle ""
		if {[regexp -nocase {document\.title\s*?=\s*?"([^"]*?)"\s*?;} $html match yttitle]} { ;#"
			append title " :: $yttitle"
		} elseif {[regexp -nocase {"title":"([^"]*?)"} $html match yttitle]} { ;#"
			append title " :: $yttitle"
		}
	}
	if {$urltitle_htmlparse} {
		set title [::htmlparse::mapEscapes $title]
	}
	return [urltitle:recode $title]
}

proc urltitle:fetch {nick host hand chan text} {
	global urltitle_ignored urltitle_flood urltitle_antiflood urltitle_max_length
	if {![channel get $chan urltitle] || [matchattr $hand $urltitle_ignored $chan]} { return }
	set now [unixtime]
	if {[info exists urltitle_flood] && ($now - $urltitle_flood) < $urltitle_antiflood} { return }
	set urltitle_flood $now
	foreach token [split $text] {
		if {![regexp -nocase {^https?://} $token] || [regexp -nocase {^https?://\[} $token] || [regexp -nocase {^https?://[^/:]+?:} $token] } { continue }
		set title [string trim [regsub -all {\s+} [urltitle:gettitle $token] " "]]
		if {$urltitle_max_length > 0 && [string length $title] > $urltitle_max_length} {
			set ctitle [string range $title 0 $urltitle_max_length]
			if {[string length $title] != [string length $ctitle]} {
				append ctitle " (...)"
			}
			set title $ctitle
		}
		if {[string length $title] > 0} {
			putlog "URL Title ($nick/$chan): $token - $title"
			puthelp "PRIVMSG $chan :\[URL] $title"
		}
		break
	}
	return 1
}

putlog "URL Title v1.4 by wilk"
