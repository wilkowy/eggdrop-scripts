# Name			Find Clones
# Author		wilk wilkowy
# Description	Finds similar users on channels
# Version		1.0 (2021..2021-07-03)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Partyline commands: .findclones

# ToDo:
# - gather real names? raw 352
# [30/18:00:42] [@] :ourserveraddr 352 botnick #channel ident host *.tld{*.pl - user server} nick status{G@} :hops{4} sid realname
# - partial match
# - search by pattern
# - search all channels

# #################################################################### #

namespace eval findclones {

	variable version "1.0"
	variable changed "2021-07-03"
	variable author "wilk"

	proc on_dcc_cmd {hand idx text} {
		if {[validchan $text]} {
			# get proper case
			set chans [channels]
			set chan [lindex $chans [lsearch -nocase -exact $chans $text]]
			find_clones $idx $chan
		} else {
			find_clones $idx
		}
		return 1
	}

	proc find_clones {idx {chname "*"}} {
		if {$chname eq "*"} {
			set chans [channels]
		} else {
			set chans [list $chname]
		}

		array set users {}
		foreach chan $chans {
			set nicks [chanlist $chan]
			foreach nick $nicks {
				set uhost [getchanhost $nick]
				if {$uhost ne ""} {
					lassign [split $uhost "@"] ident host
					set users([string tolower $nick]) [list $nick $ident $host ""]
				}
			}
		}

		set nicks [array names users]
		putdcc $idx "Users: [llength $nicks]"

		set clones [list]
		set was [list]
		foreach lnick $nicks {
			lassign $users($lnick) nick ident host realname

			if {"n,$nick" in $was || "i,$ident" in $was || "h,$host" in $was} { continue }
			lappend was "n,$nick"
			lappend was "i,$ident"
			lappend was "h,$host"
			#lappend was "r,$realname"
			#lappend was "u,$uident"			"u,$uident" in $was
			#lappend was "ih,$ident@$host"		"ih,$ident@$host" in $was
			#lappend was "uih,$uident@$host"	"uih,$uident@$host" in $was

			set uident [regsub {^[\+\^=~\-_]} $ident ""]
			set pnick [string map {"\\" "\\\\" "[" "\\[" "]" "\\]"} "*$nick*"]
			set puident [string map {"\\" "\\\\" "[" "\\[" "]" "\\]"} "*$uident*"]

			set ident_clones [list]
			set uident_clones [list]
			set host_clones [list]
			set identhost_clones [list]
			set uidenthost_clones [list]
			set pnick_clones [list]
			set pnickuident_clones [list]
			set puidentnick_clones [list]
			foreach lcnick $nicks {
				lassign $users($lcnick) cnick cident chost crealname
				set cuident [regsub {^[\+\^=~\-_]} $cident ""]

				if {[string equal -nocase $host $chost] && $cnick ni $host_clones} {
					lappend host_clones $cnick
				}
				if {[string equal -nocase $ident $cident] && $cnick ni $ident_clones} {
					lappend ident_clones $cnick
				}
				if {[string equal -nocase $uident $cuident] && $cnick ni $uident_clones} {
					lappend uident_clones $cnick
				}
				if {[string equal -nocase "$ident@$host" "$cident@$chost"] && $cnick ni $identhost_clones} {
					lappend identhost_clones $cnick
				}
				if {[string equal -nocase "$uident@$host" "$cuident@$chost"] && $cnick ni $uidenthost_clones} {
					lappend uidenthost_clones $cnick
				}
				if {[string match -nocase $pnick $cnick]} {
					lappend pnick_clones $cnick
				}
				if {[string match -nocase $pnick $cuident]} {
					lappend pnickuident_clones $cnick
				}
				if {[string match -nocase $puident $cnick]} {
					lappend puidentnick_clones $cnick
				}
			}

			set ident_clones [lsort -unique $ident_clones]
			set cnt [llength $ident_clones]
			if {$cnt > 1} {
				lappend clones "Same ident ($cnt: \"$ident\"): [join $ident_clones ", "]"
			}

			set uident_clones [lsort -unique $uident_clones]
			set cnt [llength $uident_clones]
			if {$cnt > 1 && $ident_clones ne $uident_clones} {
				lappend clones "Same ident (w/o prefix) ($cnt: \"$ident\"): [join $uident_clones ", "]"
			}

			set host_clones [lsort -unique $host_clones]
			set cnt [llength $host_clones]
			if {$cnt > 1} {
				lappend clones "Same host ($cnt: \"$host\"): [join $host_clones ", "]"
			}

			set identhost_clones [lsort -unique $identhost_clones]
			set cnt [llength $identhost_clones]
			if {$cnt > 1} {
				lappend clones "Same ident@host ($cnt: \"$ident@$host\"): [join $identhost_clones ", "]"
			}

			set uidenthost_clones [lsort -unique $uidenthost_clones]
			set cnt [llength $uidenthost_clones]
			if {$cnt > 1 && $identhost_clones ne $uidenthost_clones} {
				lappend clones "Same ident@host (w/o prefix) ($cnt: \"$uident@$host\"): [join $uidenthost_clones ", "]"
			}

			set pnick_clones [lsort -unique $pnick_clones]
			set cnt [llength $pnick_clones]
			if {$cnt > 1} {
				lappend clones "Similar nick ($cnt: \"*$nick*\"): [join $pnick_clones ", "]"
			}

			set pnickuident_clones [lsort -unique $pnickuident_clones]
			set cnt [llength $pnickuident_clones]
			if {$cnt > 1} {
				lappend clones "Nick in ident ($cnt: \"*$nick*\"): [join $pnickuident_clones ", "]"
			}

			set puidentnick_clones [lsort -unique $puidentnick_clones]
			set cnt [llength $puidentnick_clones]
			if {$cnt > 1} {
				lappend clones "Ident in nick ($cnt: \"*$uident*\"): [join $puidentnick_clones ", "]"
			}
		}

		foreach clone [lsort $clones] {
			putdcc $idx $clone
		}
	}

# -=-=-=-=-=-

	proc init {} {
		variable version; variable author
		set ns [namespace current]

		if {![info exists ::wilk::version]} {
			uplevel #0 source [file dirname [info script]]/wilk.tcl
		}
		namespace import ::wilk::*
		::wilk::register $ns

		bind dcc m|- findclones ${ns}::on_dcc_cmd

		putlog "FindClones v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind dcc m|- findclones ${ns}::on_dcc_cmd }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
	}

	init
}
