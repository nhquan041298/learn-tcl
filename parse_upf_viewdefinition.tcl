
proc READ_FILE { {FILE_NAME} } {
    set chk [file exists $FILE_NAME]
    if {$chk==0} {
        puts "* ERROR: $FILE_NAME not found."
        return -1
    }

    set fid [open $FILE_NAME]
    set CHECK_LIST {}
    while {[gets $fid str]>=0} {
        lappend CHECK_LIST $str
    }
    close $fid
    return $CHECK_LIST
}
proc debackslash_lines {raw_str} {
    set lines [split $raw_str "\n"]
    set out {}
    set cur ""
    foreach line $lines {
        set t [string trimright $line]
        # Bỏ dòng chú thích hoàn toàn
        if {[string length $t] > 0 && [string index $t 0] eq "#"} {
            continue
        }
        # Nếu dòng có # phía sau, giữ phần trước đó thôi
        set pos_hash [string first "#" $t]
        if {$pos_hash >= 0} {
            set t [string range $t 0 [expr {$pos_hash - 1}]]
            set t [string trimright $t]
        }
        # Xử lý tiếp nối dòng
        if {[string length $t] > 0 && [string index $t end] eq "\\"} {
            set t [string range $t 0 end-1]
            append cur $t " "
        } else {
            append cur $t
            if {[string length $cur] > 0} {
                lappend out [string trim $cur]
            }
            set cur ""
        }
    }
    # Nếu còn dòng cuối cùng chưa push
    if {[string length $cur] > 0} {
        lappend out [string trim $cur]
    }
    return $out
}
proc parse_create_power_domains {lines} {
    set domains {}
    foreach line $lines {
        if {[regexp {^\s*create_power_domain\s+([^\s]+)} $line -> domain]} {
            # Lấy vị trí cho -elements
            set idx_el [string first "-elements" $line]
            set idx_su [string first "-supply" $line]
            # Block elements giữa { ... } sau -elements
            set open_el [string first "{" $line $idx_el]
            set close_el [string first "}" $line $open_el]
            set block_el {}
            if {$open_el >= 0 && $close_el > $open_el} {
                set block_el [string range $line [expr {$open_el+1}] [expr {$close_el-1}]]
            }
            set elements [regexp -all -inline {\S+} $block_el]

            # Block supply giữa { ... } sau -supply
            set open_su [string first "{" $line $idx_su]
            set close_su [string first "}" $line $open_su]
            set block_su {}
            if {$open_su >= 0 && $close_su > $open_su} {
                set block_su [string range $line [expr {$open_su+1}] [expr {$close_su-1}]]
            }
            set supply ""
            set supply_tokens [regexp -all -inline {\S+} $block_su]
            if {[llength $supply_tokens]>0} {
                set supply [lindex $supply_tokens end]
            }
            lappend domains [list $domain $elements $supply]
        }
    }
    return $domains
}

