# Public Channel Commands
# by wilk wilkowy // 2007..2017-01-09

set pcc_char "!"

setudef flag chancmds

bind pub m|m ${pcc_char}o pcc:op
bind pub m|m ${pcc_char}op pcc:op
bind pub m|m ${pcc_char}do pcc:deop
bind pub m|m ${pcc_char}deop pcc:deop

bind pub v|v ${pcc_char}v pcc:voice
bind pub v|v ${pcc_char}voice pcc:voice
bind pub v|v ${pcc_char}dv pcc:devoice
bind pub v|v ${pcc_char}devoice pcc:devoice

bind pub o|o ${pcc_char}k pcc:kick
bind pub o|o ${pcc_char}kick pcc:kick
bind pub m|m ${pcc_char}b pcc:ban
bind pub m|m ${pcc_char}ban pcc:ban
bind pub m|m ${pcc_char}kb pcc:kban
bind pub m|m ${pcc_char}kickban pcc:kban
bind pub m|m ${pcc_char}ub pcc:unban
bind pub m|m ${pcc_char}unban pcc:unban

bind pub o|o ${pcc_char}t pcc:topic
bind pub o|o ${pcc_char}topic pcc:topic
bind pub n|n ${pcc_char}m pcc:mode
bind pub n|n ${pcc_char}mode pcc:mode
bind pub m|m ${pcc_char}s pcc:shutup
bind pub m|m ${pcc_char}silence pcc:shutup
bind pub m|m ${pcc_char}shutup pcc:shutup
bind pub m|m ${pcc_char}l pcc:ulimit
bind pub m|m ${pcc_char}limit pcc:ulimit
bind pub m|m ${pcc_char}ulimit pcc:ulimit
bind pub m|m ${pcc_char}unlimit pcc:ulimit
bind pub n|n ${pcc_char}lock pcc:lock
bind pub n|n ${pcc_char}unlock pcc:unlock

bind pub n|- ${pcc_char}au pcc:adduser
bind pub n|- ${pcc_char}+user pcc:adduser
bind pub n|- ${pcc_char}adduser pcc:adduser
bind pub n|- ${pcc_char}du pcc:deluser
bind pub n|- ${pcc_char}-user pcc:deluser
bind pub n|- ${pcc_char}deluser pcc:deluser
bind pub n|- ${pcc_char}ah pcc:addhost
bind pub n|- ${pcc_char}+host pcc:addhost
bind pub n|- ${pcc_char}addhost pcc:addhost

bind pub n|- ${pcc_char}rehash pcc:rehash
bind pub n|- ${pcc_char}restart pcc:restart
bind pub n|- ${pcc_char}reload pcc:reload
bind pub n|- ${pcc_char}save pcc:save
bind pub n|- ${pcc_char}backup pcc:backup
bind pub n|- ${pcc_char}die pcc:die

bind pub n|n ${pcc_char}jump pcc:jump

proc pcc:adduser {nick host hand chan text} {
	if {![pcc:ok_usr $nick $chan 0]} { return 0 }
	set _who [pcc:getarg $text]
	if {![validuser $_who]} {
		putcmdlog "<<$nick>> !$hand! adduser $_who"
		adduser $_who
	}
}

proc pcc:deluser {nick host hand chan text} {
	if {![pcc:ok_usr $nick $chan 0]} { return 0 }
	set _who [pcc:getarg $text]
	if {[validuser $_who]} {
		putcmdlog "<<$nick>> !$hand! deluser $_who"
		deluser $_who
	}
}

proc pcc:addhost {nick host hand chan text} {
	if {![pcc:ok_usr $nick $chan 0]} { return 0 }
	set _who [pcc:getarg $text]
	if {[validuser $_who]} {
		set _host [pcc:getarg $text 1]
		putcmdlog "<<$nick>> !$hand! addhost $_who $_host"
		setuser $_who HOSTS $_host
	}
}

proc pcc:op {nick host hand chan text} {
	if {![pcc:ok_bot $chan]} { return 0 }
	if {[llength $text] < 1 && ![isop $nick $chan]} {
		putcmdlog "<<$nick>> !$hand! op $chan $nick"
		pushmode $chan +o $nick
		#flushmode $chan
	} else {
		set _who ""
		foreach _nick [split [pcc:strcln $text]] {
			if {[onchan $_nick $chan] && ![isop $_nick $chan]} {
				append _who "$_nick "
				pushmode $chan +o $_nick
			}
		}
		#if {$_who ne ""} {
			putcmdlog "<<$nick>> !$hand! op $chan [string trimright $_who] ($text)"
			#flushmode $chan
		#}
	}
}

proc pcc:deop {nick host hand chan text} {
	if {![pcc:ok_bot $chan]} { return 0 }
	if {[llength $text] < 1 && [isop $nick $chan]} {
		putcmdlog "<<$nick>> !$hand! deop $chan $nick"
		pushmode $chan -o $nick
		#flushmode $chan
	} else {
		set _who ""
		set _lvl [pcc:getlvl $hand $chan]
		foreach _nick [split [pcc:strcln $text]] {
			if {[onchan $_nick $chan] && ![isbotnick $_nick] && [isop $_nick $chan]} {
				if {$_lvl >= [pcc:getlvl [nick2hand $_nick] $chan]} {
					append _who "$_nick "
					pushmode $chan -o $_nick
				}
			}
		}
		#if {$_who ne ""} {
			putcmdlog "<<$nick>> !$hand! deop $chan [string trimright $_who] ($text)"
			#flushmode $chan
		#}
	}
}

proc pcc:voice {nick host hand chan text} {
	if {![pcc:ok_bot $chan]} { return 0 }
	if {[llength $text] < 1 && ![isop $nick $chan] && ![isvoice $nick $chan]} {
		putcmdlog "<<$nick>> !$hand! voice $chan $nick"
		pushmode $chan +v $nick
		#flushmode $chan
	} else {
		set _who ""
		foreach _nick [split [pcc:strcln $text]] {
			if {[onchan $_nick $chan] && ![isop $_nick $chan] && ![isvoice $_nick $chan]} {
				append _who "$_nick "
				pushmode $chan +v $_nick
			}
		}
		#if {$_who ne ""} {
			putcmdlog "<<$nick>> !$hand! voice $chan [string trimright $_who] ($text)"
			#flushmode $chan
		#}
	}
}

proc pcc:devoice {nick host hand chan text} {
	if {![pcc:ok_bot $chan]} { return 0 }
	if {[llength $text] < 1 && [isvoice $nick $chan]} {
		putcmdlog "<<$nick>> !$hand! devoice $chan $nick"
		pushmode $chan -v $nick
		#flushmode $chan
	} else {
		set _who ""
		foreach _nick [split [pcc:strcln $text]] {
			if {[onchan $_nick $chan] && [isvoice $_nick $chan]} {
				append _who "$_nick "
				pushmode $chan -v $_nick
			}
		}
		#if {$_who ne ""} {
			putcmdlog "<<$nick>> !$hand! devoice $chan [string trimright $_who] ($text)"
			#flushmode $chan
		#}
	}
}

proc pcc:kick {nick host hand chan text} {
	if {![pcc:ok_bot $chan] || [llength $text] < 1} { return 0 }
	set _text [split [string trim $text]]
	set _who [lindex $_text 0]
	if {[onchan $_who $chan] && ![isbotnick $_who]} {
		if {[llength $_text] > 1} {
			set _reason "[join [lrange $_text 1 end]] - "
		}
		append _reason "requested by: $nick"
		if {[pcc:getlvl $hand $chan] >= [pcc:getlvl [nick2hand $_who] $chan]} {
			putcmdlog "<<$nick>> !$hand! kick $chan $_who $_reason"
			putkick $chan $_who $_reason
		}
	}
}

proc pcc:topic {nick host hand chan text} {
	if {![pcc:ok_bot $chan] || [llength $text] < 1} { return 0 }
	putcmdlog "<<$nick>> !$hand! topic $chan $text"
	putserv "TOPIC $chan :$text"
}

proc pcc:mode {nick host hand chan text} {
	if {![pcc:ok_bot $chan] || [llength $text] < 1} { return 0 }
	set _mode [lrange [split [pcc:strcln $text]] 0 6]
	putcmdlog "<<$nick>> !$hand! mode $chan $_mode"
	putserv "MODE $chan :$_mode"
}

proc pcc:shutup {nick host hand chan text} {
	if {![pcc:ok_bot $chan] || [llength $text] < 1} { return 0 }
	set _who [pcc:getarg $text]
	if {$_who ne "" && [onchan $_who $chan] && ![isbotnick $_who] && $_who != $nick} {
		if {![isvoice $nick $chan] && ![isop $nick $chan]} {
			pushmode $chan +v $nick
		}
		if {[isvoice $_who $chan]} {
			pushmode $chan -v $_who
		}
		if {[isop $_who $chan]} {
			pushmode $chan -o $_who
		}
		pushmode $chan +m
		putcmdlog "<<$nick>> !$hand! shutup $chan $_who"
	}
}

proc pcc:lock {nick host hand chan text} {
	if {![pcc:ok_bot $chan]} { return 0 }
	putcmdlog "<<$nick>> !$hand! mode $chan +im"
	pushmode $chan +im
}

proc pcc:unlock {nick host hand chan text} {
	if {![pcc:ok_bot $chan]} { return 0 }
	putcmdlog "<<$nick>> !$hand! mode $chan -im"
	pushmode $chan -im
}

proc pcc:ban {nick host hand chan text} {
	if {![pcc:ok_bot $chan] || [llength $text] < 1} { return 0 }
	set _text [split [string trim $text]]
	set _who [lindex $_text 0]
	if {[isbotnick $_who]} { return 0 }
	if {[onchan $_who $chan]} {
		if {[pcc:getlvl $hand $chan] >= [pcc:getlvl [nick2hand $_who] $chan]} {
			set _mask [maskhost [getchanhost $_who $chan]]
			#set _mask "*!*[lindex [split $_mask "!"] 1]"
		}
	} else {
		set _mask $_who
	}
	if {[llength $_text] > 1} {
		set _reason "[join [lrange $_text 1 end]] - "
	}
	append _reason "requested by: $nick"
	putcmdlog "<<$nick>> !$hand! ban $text"
	newchanban $chan $_mask $nick $_reason
}

proc pcc:kban {nick host hand chan text} {
	if {![pcc:ok_bot $chan] || [llength $text] < 1} { return 0 }
	set _text [split [string trim $text]]
	set _who [lindex $_text 0]
	if {[isbotnick $_who]} { return 0 }
	if {[onchan $_who $chan]} {
		if {[pcc:getlvl $hand $chan] >= [pcc:getlvl [nick2hand $_who] $chan]} {
			set _mask [maskhost [getchanhost $_who $chan]]
			#set _mask "*!*[lindex [split $_mask "!"] 1]"
			if {[llength $_text] > 1} {
				set _reason "[join [lrange $_text 1 end]] - "
			}
			append _reason "requested by: $nick"
			putcmdlog "<<$nick>> !$hand! kickban $text"
			newchanban $chan $_mask $nick $_reason
			putkick $chan $_who $_reason
		}
	}
}

proc pcc:unban {nick host hand chan text} {
	if {![pcc:ok_bot $chan] || [llength $text] < 1} { return 0 }
	set _mask [pcc:getarg $text]
	if {![ischanban $_mask $chan]} { return 0 }
	putcmdlog "<<$nick>> !$hand! unban $chan $_mask"
	killchanban $chan $_mask
	#pushmode $chan -b $_mask
}

proc pcc:rehash {nick host hand chan text} {
	if {![pcc:ok_usr $nick $chan]} { return 0 }
	putcmdlog "<<$nick>> !$hand! rehash"
	rehash
}

proc pcc:restart {nick host hand chan text} {
	if {![pcc:ok_usr $nick $chan]} { return 0 }
	putcmdlog "<<$nick>> !$hand! restart"
	restart
}

proc pcc:backup {nick host hand chan text} {
	if {![pcc:ok_usr $nick $chan]} { return 0 }
	putcmdlog "<<$nick>> !$hand! backup"
	backup
}

proc pcc:save {nick host hand chan text} {
	if {![pcc:ok_usr $nick $chan]} { return 0 }
	putcmdlog "<<$nick>> !$hand! save"
	save
}

proc pcc:reload {nick host hand chan text} {
	if {![pcc:ok_usr $nick $chan]} { return 0 }
	putcmdlog "<<$nick>> !$hand! reload"
	reload
}

proc pcc:die {nick host hand chan text} {
	if {![pcc:ok_usr $nick $chan]} { return 0 }
	if {[llength $text] < 1} { set text "requested by: $nick" }
	putcmdlog "<<$nick>> !$hand! die $text"
	die $text
}

proc pcc:jump {nick host hand chan text} {
	if {![pcc:ok_usr $nick $chan]} { return 0 }
	set _srv [pcc:getarg $text]
	putcmdlog "<<$nick>> !$hand! jump $_srv"
	jump $_srv
}

proc pcc:ulimit {nick host hand chan text} {
	if {![pcc:ok_bot $chan]} { return 0 }
	putcmdlog "<<$nick>> !$hand! limit $chan -l"
	pushmode $chan -l
}

proc pcc:getlvl {hand chan} {
	set _lvl 0
	if {$hand ne "*" && $hand ne ""} {
		if {[matchattr $hand v|v $chan]} { set _lvl [expr {$_lvl | 0x01}] }
		if {[matchattr $hand o|o $chan]} { set _lvl [expr {$_lvl | 0x02}] }
		if {[matchattr $hand -|m $chan]} { set _lvl [expr {$_lvl | 0x04}] }
		if {[matchattr $hand m|- $chan]} { set _lvl [expr {$_lvl | 0x08}] }
		if {[matchattr $hand -|n $chan]} { set _lvl [expr {$_lvl | 0x10}] }
		if {[matchattr $hand n|- $chan]} { set _lvl [expr {$_lvl | 0x20}] }
		if {[matchattr $hand f|f $chan]} { set _lvl [expr {$_lvl | 0x40}] }
	}
	return $_lvl
}

proc pcc:ok_bot {chan {needop 1}} {
	if {[channel get $chan chancmds] != 1} { return 0 }
	if {$needop && ![botisop $chan]} { return 0 }
	return 1
}

proc pcc:ok_usr {nick chan {needop 1}} {
	if {[channel get $chan chancmds] != 1} { return 0 }
	if {$needop && ![isop $nick $chan]} { return 0 }
	return 1
}

proc pcc:strcln {text} {
	return [string trim [regsub -all -- " +" $text " "]]
}

proc pcc:getarg {text {idx 0}} {
	return [lindex [split [pcc:strcln $text]] $idx]
}

putlog "Public Channel Commands v1.8 by wilk"
