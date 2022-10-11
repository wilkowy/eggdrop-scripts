# Name			RSS Alert
# Author		wilk wilkowy
# Description	Download RSS feeds and sends updates on channel
# Version		1.10 (2018..2021-03-22)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Required packages: http
# Optional packages: tls (best if 1.6.4+), htmlparse

# Channel flags: rssalert

# Partyline commands: .rssalert
# .rssalert help			- there are many commands so this will display built-in help
# .rssalert update			- force update of all feeds
# .rssalert publish			- publish one queued news, if any
# .rssalert list			- list all feeds with stats
# .rssalert list <id>		- list cached entries for given feed id (from "list")
# .rssalert list <url>		- list cached entries for given feed url
# .rssalert queue			- display queued news waiting to be published
# .rssalert remove <id>		- remove queued news of given id (from "queue")
# .rssalert remove <url>	- remove all queued news for given feed url (from "list")
# .rssalert stop			- remove all queued news
# .rssalert cleanup			- delete orphaned entries (not in feed list) from cache and queue
# .rssalert forget <days>	- remove cache/queue entries older than given number of days
# .rssalert forget 0		- CLEAR cache & queue (total wipe)
# .rssalert check <url>		- tries to download feed of given url and caches it
# .rssalert stats			- display number of entries in queue and cache and memory taken
# .rssalert reload			- reload database
# .rssalert save			- not really needed, just for the sake

# ToDo: per channel feeds? toggle active/hidden?

namespace eval rssalert::c {

# List of RSS news feeds to check.
# Feeds are lists composed of:
# - url
# - is_active					(1 = check for updates)
# - is_hidden					(1 = add to queue)
# - enforce_format				(0 = no, 1 = rss, 2 = atom)
# - display_author_if_present	(1 = yes)
# - publish_to_discord			(1 = yes)
# - comment

variable feeds [list	\
					[list "https://apod.nasa.gov/apod.rss" 1 0 0 0 1 "rss"] \
					[list "https://earthobservatory.nasa.gov/feeds/image-of-the-day.rss" 1 0 0 0 1 "rss"] \
					[list "https://xkcd.com/atom.xml" 1 0 0 0 1 "atom, https://xkcd.com/rss.xml"] \
				]

# Prefer direct links over feedproxy? (1 - yes)
variable skip_feedburner 1

# Fix FeedBurner BrowserFriendly enabled feeds by appending "?format=xml&fmt=xml" to url? (1 - yes)
variable fix_feedburner 1

# Remove utm_* parameters from urls? (1 - yes)
variable remove_utm_tracker 1

# Prefer update date over publishing date? (1 - yes; Atom only)
variable prefer_update 1

# Do not parse more than given number of entries per feed (prevents long loops for huge, lifetime feeds).
variable max_entries 250

# Publishing queued feeds order. (0 - random, 1 - oldest first, 2 - newest first)
variable publish_order 1

# If bot couldn't publish news anywhere should it keep it in queue? (1 - yes)
variable republish_later 1

# How many days keep entries in cache (removed each midnight)? (0 - off)
variable max_age 0

# Limit title length (0 - off) and what to append if trimmed.
variable max_title_length 0
variable trim_marker "..."

# News containing those words in title/link will be ignored ("*word*" match).
variable bad_titles [list]
variable bad_links [list "astropix.html"]

# This allows to retain cache and queue between eggdrop restarts. ("" disables backup)
variable cache_file "scripts/rssalert.db"

# CRON expression for checking news feeds.
variable cron_check "00"

# CRON expressions used for news publishing, for example one can be used for work days, the second one for weekends.
variable cron_publish1 "*/30 18-23 * * 1-5"
variable cron_publish2 "*/30 14-23 * * 0,6"

# Provide here a Discord webhook which will be treated as another output or leave it empty.
variable discord ""

# This is how script introduces itself to servers, chosen randomly.
variable user_agent [list "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:89.0) Gecko/20100101 Firefox/89.0"]

# This is accepted languages string to inform site which language version return.
variable accept_language "pl,en-US;q=0.7,en;q=0.3"

# Website fetching timeout, in miliseconds.
variable timeout 5000

# Max depth for 301/302 redirections.
variable max_redirections 5

# Save unrecognised results for further analysis? (1 - yes, 2 - save all)
variable debug 1

}

# #################################################################### #

namespace eval rssalert {

	variable version "1.10"
	variable changed "2021-03-22"
	variable author "wilk"

	namespace eval v {
		# rssid = [md5 $feedurl]
		# dataid = [md5 "$title$url"]
		# [list "$rssid,$dataid" ...]
		variable queue
		# cache($rssid,$dataid) [list $unixtime $url $title $pubdate $author]
		variable cache
		variable max_queue
	}

	proc on_dcc_cmd {hand idx text} {
		if {$text eq "help"} {
			putdcc $idx ".rssalert help            - this help"
			putdcc $idx ".rssalert stats           - display numer of entries in queue/cache and memory taken"
			putdcc $idx ".rssalert update          - forces updating all feeds"
			putdcc $idx ".rssalert publish         - forces posting one queued news"
			putdcc $idx ".rssalert list            - display feed links on partyline"
			putdcc $idx ".rssalert list <id/url>   - display cached entries for given id (from \".rssalert list\") or feed url"
			putdcc $idx ".rssalert queue           - display queued entries on partyline"
			putdcc $idx ".rssalert remove <id/url> - remove queued entries of given id (from \".rssalert queue\") or feed url"
			putdcc $idx ".rssalert stop            - clear queue and hence stop posting messages"
			putdcc $idx ".rssalert cleanup         - remove orphaned cache entries (without url in feeds) and clean queue if needed"
			putdcc $idx ".rssalert forget <days>   - remove cache entries older than given days (since collecting not a real news age)"
			putdcc $idx ".rssalert forget 0        - remove ALL queued and cached entries"
			putdcc $idx ".rssalert check <url>     - check given feed url (without adding to queue, but with cacheing)"
			putdcc $idx ".rssalert save            - save database"
			putdcc $idx ".rssalert reload          - reload database"
		} elseif {[regexp -nocase {^forget (\d+)$} $text match arg]} {
			clear_cache $idx $arg
		} elseif {$text eq "stop"} {
			remove_queued $idx
		} elseif {$text eq "update"} {
			on_cron_update 0 0 0 0 0
		} elseif {$text eq "publish"} {
			on_cron_publish 0 0 0 0 0
		} elseif {$text eq "queue"} {
			show_queue $idx
		} elseif {$text eq "cleanup"} {
			cleanup_cache $idx
		} elseif {$text eq "list"} {
			list_feeds $idx
		} elseif {$text eq "stats"} {
			show_stats $idx
		} elseif {$text eq "save"} {
			save_database
		} elseif {$text eq "reload"} {
			load_database
		} elseif {[regexp -nocase {^list (.+)$} $text match arg]} {
			list_feed $idx $arg
		} elseif {[regexp -nocase {^remove (.+)$} $text match arg]} {
			remove_queued $idx $arg
		} elseif {[regexp -nocase {^check (.+)$} $text match arg]} {
			# we fix_feedburner inside
			fetch_feed $arg 0 0 $idx
		} else {
			putdcc $idx "Usage: .rssalert <help/update/publish/list \[id/url]/queue/remove <id/url>/stop/cleanup/forget <days/0>/check <url>/stats/save/reload>"
			return
		}
		return 1
	}

	proc fetch_feed {rssurl format noqueue {idx -1}} {
		if {$c::fix_feedburner && [string match -nocase "*.feedburner.com/*" $rssurl]} {
			set rssurl "$rssurl?format=xml&fmt=xml"
		}
		set accept_content "application/atom+xml,application/rss+xml,application/xml,text/xml"
		set xml [string map {"\r" "" "\n" "" "\t" ""} [get_html $rssurl [lrandom $c::user_agent] $accept_content $c::accept_language $c::timeout $c::max_redirections]]
		if {[string length $xml] == 0} { return }
		if {$format == 2 || [regexp -nocase {<feed[^>]+?xmlns=["']https?://www\.w3\.org/2005/Atom["']} $xml]} {
			set atom 1
			set tag_open "<entry" ; set tag_close "</entry>"
		} elseif {$format == 1 || [regexp -nocase {<rss[^>]+?version="2\.0"} $xml] || [regexp -nocase {xmlns="https?://purl\.org/rss/1\.0/"} $xml]} {
			set atom 0
			set tag_open "<item" ; set tag_close "</item>"
		} else {
			putlog "RSSAlert: unknown feed type for $rssurl"
			debug_save $c::debug 0 "err : $rssurl" "rssalert"
			return
		}
		set rsstype(0) "rss"
		set rsstype(1) "atom"
		if {$idx >= 0} {
			putdcc $idx "* Feed $rssurl ($rsstype($atom)):"
		}
		set rssid [md5 $rssurl]
		set newfeed 0
		if {[llength [array names v::cache "$rssid,*"]] == 0} {
			set newfeed 1
		}
		set items [set invalid [set ignored [set known [set new 0]]]]
		set now [unixtime]
		set max_entries $c::max_entries
		while {1} {
			if {$max_entries <= 0} { break }
			incr max_entries -1
			set entry_start [string first $tag_open $xml]
			set entry_end [string first $tag_close $xml]
			if {$entry_start == -1 || $entry_end == -1} { break }
			incr entry_end [string length $tag_close]
			set entry [string range $xml $entry_start $entry_end]
			set xml [string range $xml $entry_end end]
			set guid [set author [set update [set pubdate [set title [set fblink [set link ""]]]]]]
			if {$atom} {
				regexp -nocase {<id>([^<>]*?)</id>} $entry match guid
				regexp -nocase {<title[^>]*?>(?:<!\[CDATA\[)?([^<>]*?)(?:]]>)?</title>} $entry match title
				regexp -nocase {<link[^>]+?rel=["']alternate["'][^>]+?href=["']([^"']+?)["'][^>]*?(?:/>|></link>)} $entry match link ;#"
				if {[string trim $link] eq ""} {
					regexp -nocase {<link[^>]+?href=["']([^"']+?)["'][^>]*?(?:/>|></link>)} $entry match link ;#"
				}
				regexp -nocase {<feedburner:origLink>([^<>]+?)</feedburner:origLink>} $entry match fblink
				regexp -nocase {<published>([^<>]*?)</published>} $entry match pubdate
				regexp -nocase {<updated>([^<>]*?)</updated>} $entry match update
				regexp -nocase {<author>(?:<email>[^<>]*?</email>)?<name>(?:<!\[CDATA\[)?([^<>]*?)(?:]]>)?</name>(?:<email>[^<>]*?</email>)?</author>} $entry match author
			} else {
				regexp -nocase {<guid[^>]*?>([^<>]*?)</guid>} $entry match guid
				regexp -nocase {<title>(?:<!\[CDATA\[)?([^<>]*?)(?:]]>)?</title>} $entry match title
				regexp -nocase {<link>([^<>]+?)</link>} $entry match link
				if {[string trim $link] eq ""} {
					regexp -nocase {<link[^>]+?href=["']([^"']+?)["'][^>]*?(?:/>|></link>)} $entry match link ;#"
				}
				regexp -nocase {<feedburner:origLink>([^<>]+?)</feedburner:origLink>} $entry match fblink
				regexp -nocase {<pubDate>([^<>]*?)</pubDate>} $entry match pubdate
				if {[string trim $pubdate] eq ""} {
					regexp -nocase {<dc:date>([^<>]*?)</dc:date>} $entry match pubdate
				}
				regexp -nocase {<author>(?:<!\[CDATA\[)?([^<>]*?)(?:]]>)?</author>} $entry match author
				if {[string trim $author] eq ""} {
					regexp -nocase {<dc:creator>(?:<!\[CDATA\[)?([^<>]*?)(?:]]>)?</dc:creator>} $entry match author
				}
			}
			set guid [string trim $guid]
			set title [string trim $title]
			set link [string trim $link]
			set fblink [string trim $fblink]
			set pubdate [string trim $pubdate]
			set update [string trim $update]
			set author [string trim $author]
			if {$c::skip_feedburner && $fblink ne ""} { set link $fblink }
			if {$c::prefer_update && $update ne ""} { set pubdate $update }
			if {$guid eq ""} { set guid $link }
			set guid [decode_entities $guid]
			set title [decode_entities $title]
			set link [decode_entities $link]
			if {$c::remove_utm_tracker} {
				set link [string trimright [regsub -all {(?:utm_source|utm_medium|utm_campaign|utm_term|utm_content)=[^&]+&?} $link ""] "?&"]
			}
			set title [trim_text [string trim [recode_html $title]] $c::max_title_length $c::trim_marker]
			#set dataid [md5 "$title$link$pubdate"]
			set dataid [md5 "$title$link"] ;# some feeds suck with randomly changing pubdate
			if {$link eq "" || $title eq ""} {
				incr invalid
				continue
			}
			incr items
			if {$idx >= 0} {
				putdcc $idx "| $title :: $link"
			}
			if {[info exists v::cache($rssid,$dataid)]} {
				incr known
				set timestamp [lindex $v::cache($rssid,$dataid) 0]
				set v::cache($rssid,$dataid) [list $timestamp $link $title $pubdate $author]
			} else {
				incr new
				if {!$newfeed} {
					set bad 0
					foreach badword $c::bad_titles {
						if {[string match -nocase "*$badword*" $title]} {
							set bad 1
							break
						}
					}
					if {!$bad} {
						foreach badword $c::bad_links {
							if {[string match -nocase "*$badword*" $link]} {
								set bad 1
								break
							}
						}
					}
					if {$bad} {
						incr ignored
					} elseif {$idx < 0 && !$noqueue} {
						lappend v::queue "$rssid,$dataid"
					}
				}
				set v::cache($rssid,$dataid) [list $now $link $title $pubdate $author]
			}
		}
		if {$idx >= 0} {
			putdcc $idx "* Items: $items, known: $known, ignored: $ignored, invalid: $invalid"
			save_database
		} else {
			set msg "$rsstype($atom), new: $new, known: $known"
			if {$ignored > 0} {
				append msg ", ignored: $ignored"
			}
			if {$invalid > 0} {
				append msg ", invalid: $invalid"
			}
			if {$newfeed} {
				append msg ", first update"
			}
			putlog "RSSAlert: updated $rssurl ($msg)"
		}
	}

	proc on_cron_update {minute hour day month weekday} {
		set before [llength $v::queue]
		foreach feed $c::feeds {
			lassign $feed rssurl is_active is_hidden enforce_format show_author send_discord comment
			if {$is_active} {
				# we fix_feedburner inside
				fetch_feed $rssurl $enforce_format $is_hidden
			}
		}
		set after [llength $v::queue]
		set new [expr {$after - $before}]
		putlog "RSSAlert: new items: $new (queued: $after)"
		if {$after > $v::max_queue} { set v::max_queue $after }
		save_database
		return
	}

	proc on_cron_publish {minute hour day month weekday} {
		set cnt [llength $v::queue]
		if {$cnt == 0} { return }
		if {$cnt == 1 || $c::publish_order == 0} {
			set selected [rand $cnt]
		} else {
			set num [set max_num [set min_num 0]]
			set max 0
			set min 9999999999
			foreach id $v::queue {
				if {![info exists v::cache($id)]} { continue }
				set timestamp [lindex $v::cache($id) 0]
				if {$timestamp > $max} {
					set max $timestamp
					set max_num $num
				} elseif {$timestamp < $min} {
					set min $timestamp
					set min_num $num
				}
				incr num
			}
			if {$c::publish_order == 1} {
				# 1 oldest first
				set selected $min_num
			} elseif {$c::publish_order == 2} {
				# 2 newest first
				set selected $max_num
			}
			# set selected 0
			# set selected "end"
		}
		set id [lindex $v::queue $selected]
		set v::queue [lreplace $v::queue $selected $selected]
		if {![info exists v::cache($id)]} { return }
		lassign $v::cache($id) timestamp url title date author
		set rssid [lindex [split $id ","] 0]
		set show_author 0
		set send_discord 0
		foreach feed $c::feeds {
			set rssurl [lindex $feed 0]
			if {$c::fix_feedburner && [string match -nocase "*.feedburner.com/*" $rssurl]} {
				set rssurl "$rssurl?format=xml&fmt=xml"
			}
			if {[md5 $rssurl] eq $rssid} {
				lassign $feed rssurl is_active is_hidden enforce_format show_author send_discord comment
				break
			}
		}
		# $chan   - channel
		# $url    - news url
		# $title  - news title
		# $date   - publication/update date
		# $author - author
		set msg "$url <=> $title"
		if {$show_author && $author ne ""} {
			append msg " ~ $author"
		}
		set published 0
		foreach chan [channels] {
			if {![channel get $chan rssalert]} { continue }
			if {![botonchan $chan]} {
				putlog "RSSAlert: unable to publish - not on channel ($chan)"
				continue
			}
			sendmsg $chan "\[RSS] $msg"
			incr published
		}
		if {$send_discord && $c::discord ne ""} {
			set clnauthor [string map {"*" "" "_" "" "~" ""} $author]
			set content "Pojawił się nowy wpis"
			if {$show_author && $clnauthor ne ""} {
				append content " **$clnauthor**"
			}
			set content [json_str "$content: $url\n„$title”"]
			set json "{\"content\":\"$content\"}"
			set ncode [rest_api $c::discord $json [lrandom $c::user_agent] $c::timeout]
			if {![string match "2*" $ncode]} {
				putlog "RSSAlert: sending to Discord failed ($ncode)"
			}
		}
		if {$published} {
			putlog "RSSAlert: published $url"
		} elseif {$c::republish_later} {
			lappend v::queue $id
		}
		save_database
		return
	}

	proc list_feeds {idx} {
		set feeds [llength $c::feeds]
		putdcc $idx "* Active feeds: $feeds"
		set other [llength [array names v::cache]]
		set pos 1
		if {$feeds > 0} {
			putdcc $idx "| #ID OLDEST NEWEST CACHED QUEUED AUTHOR DISCORD HIDDEN ACTIVE FORMAT URL"
			putdcc $idx "|     (days) (days)"
		}
		foreach feed $c::feeds {
			lassign $feed rssurl is_active is_hidden enforce_format show_author send_discord comment
			if {$c::fix_feedburner && [string match -nocase "*.feedburner.com/*" $rssurl]} {
				set rssurl "$rssurl?format=xml&fmt=xml"
			}
			set rssid [md5 $rssurl]
			set cache [array names v::cache "$rssid,*"]
			set cached [llength $cache]
			incr other -$cached
			set queued [llength [lsearch -all $v::queue "$rssid,*"]]
			if {$cached != 0} {
				set oldest 0
				set newest 9999999999
				set now [unixtime]
				foreach id $cache {
					set timestamp [lindex $v::cache($id) 0]
					set diff [expr {$now - $timestamp}]
					if {$diff > $oldest} {
						set oldest $diff
					} elseif {$diff < $newest} {
						set newest $diff
					}
				}
				set oldest [expr {$oldest / 86400}]
				set newest [expr {$newest / 86400}]
			} else {
				set oldest 0
				set newest 0
			}
			set format [lindex [list "detect" "rss" "atom"] $enforce_format]
			putdcc $idx [format "| #%-2d %6d %6d %6d %6d %6d %7d %6d %6d %6s %s" $pos $oldest $newest $cached $queued $show_author $send_discord $is_hidden $is_active $format $rssurl]
			incr pos
		}
		if {$other > 0} {
			putdcc $idx "| orphans in cache: $other"
		}
	}

	proc list_feed {idx item} {
		if {![string is digit $item]} {
			set rssurl $item
		} elseif {$item > 0 && $item <= [llength $c::feeds]} {
			set rssurl [lindex [lindex $c::feeds $item-1] 0]
		} else {
			return
		}
		if {$c::fix_feedburner && [string match -nocase "*.feedburner.com/*" $rssurl]} {
			set rssurl "$rssurl?format=xml&fmt=xml"
		}
		set rssid [md5 $rssurl]
		set cache [array names v::cache "$rssid,*"]
		set count [llength $cache]
		putdcc $idx "* Feed: $rssurl, items: $count"
		set pos 1
		foreach id $cache {
			lassign $v::cache($id) timestamp url title date author
			set msg "$url <=> $title"
			if {$date ne ""} {
				append msg " <=> $date"
			}
			if {$author ne ""} {
				append msg " <=> $author"
			}
			putdcc $idx "| #$pos: $msg"
			incr pos
		}
	}

	proc show_queue {idx} {
		set queued [llength $v::queue]
		putdcc $idx "* Queued entries: $queued"
		set pos 1
		foreach id $v::queue {
			if {![info exists v::cache($id)]} { continue }
			lassign $v::cache($id) timestamp url title date author
			putdcc $idx "| #$pos: $url <=> $title"
			incr pos
		}
	}

	proc remove_queued {idx {item ""}} {
		set removed 0
		set items [llength $v::queue]
		if {$item eq ""} {
			set removed $items
			set v::queue [list]
		} elseif {![string is digit $item]} {
			set rssid [md5 $item]
			set v::queue [lsearch -all -inline -not $v::queue "$rssid,*"]
			set removed [expr {$items - [llength $v::queue]}]
		} elseif {$item > 0 && $item <= $items} {
			set v::queue [lreplace $v::queue $item-1 $item-1]
			incr removed
		}
		putdcc $idx "* Queue entries removed: $removed"
		save_database
	}

	proc cleanup_cache {idx} {
		set removed [llength [array names v::cache]]
		set valid [list]
		foreach feed $c::feeds {
			set rssurl [lindex $feed 0]
			if {$c::fix_feedburner && [string match -nocase "*.feedburner.com/*" $rssurl]} {
				set rssurl "$rssurl?format=xml&fmt=xml"
			}
			set rssid [md5 $rssurl]
			set cache [array get v::cache "$rssid,*"]
			set valid [concat $valid $cache]
		}
		unset -nocomplain v::cache
		array set v::cache $valid
		incr removed -[llength [array names v::cache]]
		putdcc $idx "* Orphaned cache entries removed: $removed"
		set removed [llength $v::queue]
		set valid [list]
		foreach id $v::queue {
			if {[info exists v::cache($id)]} {
				lappend valid $id
			}
		}
		set v::queue $valid
		incr removed -[llength $v::queue]
		putdcc $idx "* Orphaned queue entries removed: $removed"
		save_database
	}

	proc clear_cache {idx days} {
		if {$days > 0} {
			lassign [drop_cache $days] cached_removed queued_removed
			putdcc $idx "* Cache entries removed: $cached_removed"
			putdcc $idx "* Queue entries removed: $queued_removed"
		} else {
			set removed [llength [array names v::cache]]
			unset -nocomplain v::cache
			putdcc $idx "* Cache entries removed: $removed"
			remove_queued $idx
		}
		save_database
	}

	proc drop_cache {days} {
		set now [unixtime]
		set queued_removed [set cached_removed 0]
		foreach id [array names v::cache] {
			set timestamp [lindex $v::cache($id) 0]
			if {($now - $timestamp) / 86400 >= $days} {
				unset v::cache($id)
				incr cached_removed
				set items [llength $v::queue]
				set v::queue [lsearch -all -inline -not -exact $v::queue $id]
				incr queued_removed [expr {$items - [llength $v::queue]}]
			}
		}
		return [list $cached_removed $queued_removed]
	}

	proc show_stats {idx} {
		set count [llength $c::feeds]
		set cword [flex $count "feed" "feeds" "feeds"]
		putdcc $idx "* Feeds: $count $cword"
		set count [llength [array names v::cache]]
		set size [string bytelength [array get v::cache]]
		set cword [flex $count "entry" "entries" "entries"]
		set sword [flex $size "byte" "bytes" "bytes"]
		putdcc $idx "* Cache: $count $cword taking $size $sword"
		set count [llength $v::queue]
		set size [string bytelength $v::queue]
		set cword [flex $count "entry" "entries" "entries"]
		set sword [flex $size "byte" "bytes" "bytes"]
		putdcc $idx "* Queue: $count $cword (max: $v::max_queue) taking $size $sword"
	}

	proc on_time_cleanup {minute hour day month year} {
		if {$c::max_age <= 0} { return }
		lassign [drop_cache $c::max_age] cached_removed queued_removed
		putlog "RSSAlert: old entries removed - cache: $cached_removed, queue: $queued_removed"
		return
	}

	proc load_database {} {
		if {$c::cache_file eq "" || ![file exists $c::cache_file] || [file size $c::cache_file] <= 0} { return }
		set file [open $c::cache_file r]
		unset -nocomplain v::cache
		array set v::cache [gets $file]
		set v::queue [gets $file]
		close $file
	}

	proc save_database {} {
		if {$c::cache_file eq ""} { return }
		set file [open $c::cache_file w 0600]
		puts $file [array get v::cache]
		puts $file $v::queue
		close $file
	}

	proc on_event_save {event} {
		putlog "RSSAlert: saving database file"
		save_database
		return
	}

# -=-=-=-=-=-

	proc init {} {
		variable version; variable author
		set ns [namespace current]

		if {![info exists ::wilk::version]} {
			uplevel #0 source [file dirname [info script]]/wilk.tcl
		}
		namespace import ::wilk::*

		if {![init_http]} {
			putlog "RSSAlert: script not loaded"
			return
		}

		::wilk::register $ns

		if {![array exists v::cache]} { array set v::cache {} }
		if {![info exists v::queue]} { set v::queue [list] }
		if {![info exists v::max_queue]} { set v::max_queue 0 }

		setudef flag rssalert

		load_database

		bind cron - $c::cron_check ${ns}::on_cron_update

		bind cron - $c::cron_publish1 ${ns}::on_cron_publish
		bind cron - $c::cron_publish2 ${ns}::on_cron_publish

		bind time - "00 00 *" ${ns}::on_time_cleanup

		bind evnt - save ${ns}::on_event_save

		bind dcc n|- rssalert ${ns}::on_dcc_cmd

		putlog "RSSAlert v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind cron - $c::cron_check ${ns}::on_cron_update }
		catch { unbind cron - $c::cron_publish1 ${ns}::on_cron_publish }
		catch { unbind cron - $c::cron_publish2 ${ns}::on_cron_publish }
		catch { unbind time - "00 00 *" ${ns}::on_time_cleanup }
		catch { unbind evnt - save ${ns}::on_event_save }
		catch { unbind dcc n|- rssalert ${ns}::on_dcc_cmd }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag rssalert
	}

	init
}
