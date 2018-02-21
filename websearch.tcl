# Name		WebSearch
# Author	wilk wilkowy
# Version	1.2 (2018..2018-02-20)
# License	GNU GPL v2 or any later version

# Users having this flags are ignored.
set websearch_ignored "I|I"

# Users having this flags can trigger script.
set websearch_allowed "v|v"

# Command prefix.
set websearch_prefix "!"

# Protect against floods, in seconds (0 - off).
set websearch_antiflood 5

# Protect against web floods, in seconds per engine (0 - off).
set websearch_webantiflood 30

# This is how script introduces itself to servers, chosen randomly.
set websearch_agent [list "Mozilla/5.0 (X11; Linux x86_64; rv:57.0) Gecko/20100101 Firefox/57.0"]

# Website fetching timeout, in miliseconds.
set websearch_timeout 5000

# Max depth for 301/302 redirections.
set websearch_max_depth 5

# On/off .chanset flag.
setudef flag websearch

bind pub $websearch_allowed ${websearch_prefix}google websearch:search_google
bind pub $websearch_allowed ${websearch_prefix}goog websearch:search_google
bind pub $websearch_allowed ${websearch_prefix}goo websearch:search_google
bind pub $websearch_allowed ${websearch_prefix}g websearch:search_google
bind pub $websearch_allowed ${websearch_prefix}duckduckgo websearch:search_ddg
bind pub $websearch_allowed ${websearch_prefix}duck websearch:search_ddg
bind pub $websearch_allowed ${websearch_prefix}ddg websearch:search_ddg
bind pub $websearch_allowed ${websearch_prefix}d websearch:search_ddg
bind pub $websearch_allowed ${websearch_prefix}bing websearch:search_bing
bind pub $websearch_allowed ${websearch_prefix}b websearch:search_bing
bind pub $websearch_allowed ${websearch_prefix}yandex websearch:search_yandex
bind pub $websearch_allowed ${websearch_prefix}yan websearch:search_yandex
bind pub $websearch_allowed ${websearch_prefix}y websearch:search_yandex
bind pub $websearch_allowed ${websearch_prefix}youtube websearch:search_youtube
bind pub $websearch_allowed ${websearch_prefix}yt websearch:search_youtube

package require http
if {![catch {set websearch_tlsver [package require tls]}]} {
	set websearch_tls 1
	if {[package vcompare $websearch_tlsver 1.6.4] < 0} {
		putlog "Web Search: tls package version <1.6.4 = no SNI support, HTTPS links might not work properly"
	}
} else {
	set websearch_tls 0
	putlog "Web Search: no tls package = no SSL/TLS support (HTTPS protocol), script will not work properly"
}
if {![catch {package require htmlparse}]} {
	set websearch_htmlparse 1
} else {
	set websearch_htmlparse 0
	putlog "Web Search: no htmlparse package = no escape sequences substitution"
}

proc websearch:tlssocket {args} {
	global websearch_tlsver
	set opts [lrange $args 0 end-2]
	set host [lindex $args end-1]
	set port [lindex $args end]
	if {[package vcompare $websearch_tlsver 1.7.11] >= 0} {
		::tls::socket -tls1 1 -tls1.1 1 -tls1.2 1 -ssl3 0 -ssl2 0 -autoservername 1 {*}$opts $host $port
	} elseif {[package vcompare $websearch_tlsver 1.6.4] >= 0} {
		::tls::socket -tls1 1 -tls1.1 1 -tls1.2 1 -ssl3 0 -ssl2 0 -servername $host {*}$opts $host $port
	} else {
		::tls::socket -tls1 1 -ssl3 0 -ssl2 0 {*}$opts $host $port
	}
}

proc websearch:gethtml {query depth {referer ""} {cookies ""}} {
	global websearch_tls websearch_agent websearch_timeout websearch_state
	if {[string length $query] == 0 || $depth < 0} { return "" }
	if {$websearch_tls && [string match -nocase "https://*" $query]} {
		::http::register https 443 websearch:tlssocket
	}
	::http::config -useragent [lindex $websearch_agent [rand [llength $websearch_agent]]]
	if {[llength $cookies] > 0} {
		catch { set http [::http::geturl $query -timeout $websearch_timeout -headers [list "Referer" $referer "Cookie" [string trim [join $cookies ";"] ";"]]] } httperror
	} else {
		catch { set http [::http::geturl $query -timeout $websearch_timeout] } httperror
	}
	if {![info exists http]} {
		putlog "Web Search: connection error for $query ($httperror)"
		return ""
	}
	set status [::http::status $http]
	set code [::http::ncode $http]
	set html ""
	if {$status eq "ok"} {
		upvar #0 $http state
		array set websearch_state [array get state]
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
				if {$websearch_tls} {
					#::http::unregister https
				}
				set addr ""
				if {[regexp -nocase {^https?://[^/&?]+?} $query addr] && ![regexp -nocase {^https?://} $redir]} {
					set redir "$addr$redir"
				}
				return [websearch:gethtml $redir [expr {$depth - 1}] $addr $cook]
			}
		}
		if {[string match -nocase "text/html*" $state(type)]} {
			set html [::http::data $http]
		} else {
			putlog "Web Search: invalid content-type for $query ($state(type))"
		}
	} else {
		putlog "Web Search: connection failed for $query ($status)"
	}
	::http::cleanup $http
	if {$websearch_tls} {
		#::http::unregister https
	}
	return $html
}

proc websearch:_search {chan nick engine query link} {
	global websearch_max_depth websearch_htmlparse
	set query [string trim $query]
	if {$query eq ""} { return }
	set words [list]
	foreach word [split $query] {
		lappend words [::http::formatQuery $word]
	}
	set equery [join $words "+"]
	set url "$link$equery"
	array set ename [list 1 "Google" 2 "DuckDuckGo" 3 "Bing" 4 "Yandex" 5 "YouTube"]
	set html [string map -nocase {"\r" "" "\n" "" "<b>" "" "</b>" "" "<strong>" "" "</strong>" "" "<b class=\"needsclick\">" ""} [websearch:gethtml $url $websearch_max_depth]]
	set link [set desc ""]
	switch $engine {
		1	{
				regexp -nocase {<h3[^>]+?class="r"[^>]*?>\s*?<a[^>]+?href="([^"]+?)"[^>]*?">([^<>]+?)</a>\s*?</h3>} $html match link desc
			}
		2	{
				regexp -nocase {<h2[^>]+?class="result__title"[^>]*?>\s*?<a[^>]+?href="([^"]+?)"[^>]*?>([^<>]+?)</a>\s*?</h2>} $html match link desc ;#"
			}
		3	{
				regexp -nocase {<h2>\s*?<a[^>]+?href="([^"]+?)"[^>]*?>([^<>]+?)</a>\s*?</h2>} $html match link desc ;#"
			}
		4	{
				regexp -nocase {<h2[^>]+?class="organic__title[^/]+?/div>\s*?<a[^>]+?class="link[^>]+?href="([^"]+?)"[^>]*?>[^/]+?/div></div>([^<>]+?)</a>\s*?</h2>} $html match link desc ;#"
			}
		5	{
				if {[regexp -nocase {"videoRenderer":\{"videoId":"([^"]+?)".+?"title":.+?"simpleText":"([^"]+?)"} $html match link desc]} {
					set link "https://www.youtube.com/watch?v=$link"
				}
			}
	}
	if {[string length $link] > 0} {
		set desc [string trim [regsub -all {\s+} $desc " "]]
		if {$websearch_htmlparse} {
			set desc [::htmlparse::mapEscapes $desc]
		}
		putlog "Web Search ($nick/$chan): $url - $link - $desc"
		puthelp "PRIVMSG $chan :\[$ename($engine)] $link <=> $desc"
	} elseif {[string length $html] > 0} {
		putlog "Web Search: something went wrong for query $url"
	}
}

proc websearch:search {chan nick hand engine query link} {
	global websearch_ignored websearch_flood websearch_antiflood websearch_webflood websearch_webantiflood
	if {![channel get $chan websearch] || [matchattr $hand $websearch_ignored $chan]} { return }
	set now [unixtime]
	if {[info exists websearch_flood] && ($now - $websearch_flood) < $websearch_antiflood} { return }
	set websearch_flood $now
	if {[info exists websearch_webflood($engine)] && ($now - $websearch_webflood($engine)) < $websearch_webantiflood} {
		array set ename [list 1 "Google" 2 "DuckDuckGo" 3 "Bing" 4 "Yandex" 5 "YouTube"]
		puthelp "PRIVMSG $chan :\[$ename($engine)] Zbyt czeste zapytania (co ${websearch_webantiflood}s, zostalo [expr {$websearch_webantiflood - ($now - $websearch_webflood($engine))}]s)."
		return
	}
	set websearch_webflood($engine) $now
	websearch:_search $chan $nick $engine $query $link
}

proc websearch:search_all {nick host hand chan text} {
	websearch:_search $chan $nick 1 $text "https://www.google.pl/search?q="
	websearch:_search $chan $nick 2 $text "https://duckduckgo.com/html/?q="
	websearch:_search $chan $nick 3 $text "https://www.bing.com/search?q="
	websearch:_search $chan $nick 4 $text "https://www.yandex.com/search/?text="
	websearch:_search $chan $nick 5 $text "https://www.youtube.com/results?search_query="
	return 1
}

proc websearch:search_google {nick host hand chan text} {
	websearch:search $chan $nick $hand 1 $text "https://www.google.pl/search?q="
	return 1
}

proc websearch:search_ddg {nick host hand chan text} {
	websearch:search $chan $nick $hand 2 $text "https://duckduckgo.com/html/?q="
	return 1
}

proc websearch:search_bing {nick host hand chan text} {
	websearch:search $chan $nick $hand 3 $text "https://www.bing.com/search?q="
	return 1
}

proc websearch:search_yandex {nick host hand chan text} {
	websearch:search $chan $nick $hand 4 $text "https://www.yandex.com/search/?text="
	return 1
}

proc websearch:search_youtube {nick host hand chan text} {
	websearch:search $chan $nick $hand 5 $text "https://www.youtube.com/results?search_query="
	return 1
}

putlog "Web Search v1.2 by wilk"
