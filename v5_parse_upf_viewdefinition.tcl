#!/usr/bin/env tclsh8.5

# PROC 1: Read entire file into string
proc read_entire_file {filename} {
    # If file not exist raise Error
    if {![file exists $filename]} {
        error "File not found: $filename"
        return -1
    }
    set fh [open $filename "r"]
    # Read by  encoding , avoid specical character
    fconfigure $fh -translation binary -encoding utf-8
    set data [read $fh]
    close $fh
    # Return raw data
    return $data
}

# PROC 2: Remove back slash  and stich line, remove comment
proc debackslash_lines {raw_str} {
    set lines [split $raw_str "\n"]
    set out {}
    set cur ""
    foreach line $lines {
        set t [string trimright $line]
        # Remove command line
        if {[string length $t] > 0 && [string index $t 0] eq "#"} {
            continue
        }
        # If line has # at the end of line, only keep the previous part.
        set pos_hash [string first "#" $t]
        if {$pos_hash >= 0} {
            set t [string range $t 0 [expr {$pos_hash - 1}]]
            set t [string trimright $t]
        }
        # Process stich line
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
    # If the last line still not push
    if {[string length $cur] > 0} {
        lappend out [string trim $cur]
    }
    return $out
}

# PROC 3: collect data after option.
proc extract_block_after_option {line option} {
    # Find the index of option
    set idx_opt [string first $option $line]
    if {$idx_opt < 0} { return {} }
    # Find open backet after option
    set idx_start [string first "{" $line $idx_opt]
    if {$idx_start < 0} { return {} }
    # Find the close bracket after idx_start
    set idx_end [string first "}" $line $idx_start]
    if {$idx_end < 0} { return {} }
    # Get the string between { }
    set block [string range $line [expr {$idx_start + 1}] [expr {$idx_end - 1}]]
    set info [regexp -all -inline {\S+} $block]
    return $info
}

# PROC 4: parse main domain.
proc parse_main_domain {line} {
    # Domain name
    set domname [lindex [regexp -all -inline {\S+} $line] 1]
    # Get supply
    set supply_toks [extract_block_after_option $line "-supply"]
    # Only get the supply, not get the "Primary" string
    set supply ""
    if {[llength $supply_toks] > 1} {
        set supply [lindex $supply_toks end]
    } elseif {[llength $supply_toks] == 1} {
        set supply [lindex $supply_toks 0]
    }
    return [list $domname $supply]
}

# PROC 5: parse normal domain.
proc parse_normal_domain {line} {
    set domname [lindex [regexp -all -inline {\S+} $line] 1] 
    set elements [extract_block_after_option $line "-elements"]
    set supply_toks [extract_block_after_option $line "-supply"]
    set supply ""
    if {[llength $supply_toks] > 1} {
        set supply [lindex $supply_toks end]
    } elseif {[llength $supply_toks] == 1} {
        set supply [lindex $supply_toks 0]
    }
    return [list $domname $supply $elements]
}

# PROC 6: main parse upf command - action
proc parse_upf {filename } {
    set lines [debackslash_lines [read_entire_file $filename]]
    set main_domains {}
    set normal_domains {}

    foreach line $lines {
        if {[string match "create_power_domain *-include_scope*" $line]} {
            # Case: main domain (have -include_scope)
            lappend main_domains [parse_main_domain $line]
        } elseif {[string match "create_power_domain *-elements*" $line]} {
            # Case: domain normal
            lappend normal_domains [parse_normal_domain $line]
        }
        # Can add-on another upf command case and each action here.
    }
    return [dict create main_domains $main_domains normal_domains $normal_domains]
}

# PROC 7: print upf_note - only for debug/cross check.
proc print_parse_upf_note  { upf_dict notefile} {
    set FID [open $notefile w]
     if {[dict exists $upf_dict main_domains]} { set main_domains [dict get $upf_dict main_domains] } else { set main_domains {} }
     if {[dict exists $upf_dict normal_domains]} { set normal_domains [dict get $upf_dict normal_domains] } else { set normal_domains {} }
    #puts "==== MAIN DOMAINS ===="
    foreach d $main_domains {
        puts $FID "-default_pd  [lindex $d 0]  [lindex $d 1]"
    }
    #puts "==== NORMAL DOMAINS ===="
    foreach d $normal_domains {
        puts $FID "-pwr_domain  [lindex $d 0]  [lindex $d 1]  [join [lindex $d 2] " "]"
    }
    close $FID
}

# ======= VIEW PARSE ========
# PROC 8: collect data after option with variable infor.
proc extract_block_after_option_v2 {line_string option dict_var} {
    set result {}

    # Tìm vị trí của option
    set opt_idx [string first $option $line_string]
    if {$opt_idx == -1} {
        return $result
    }

    # Cắt phần sau option
    set remain [string range $line_string [expr {$opt_idx + [string length $option]}] end]
    set remain [string trimleft $remain]

    # Trường hợp 1: dấu ngoặc nhọn {…}
    if {[string match {\{*} $remain]} {
        set close_idx [string first \} $remain]
        if {$close_idx > 0} {
            set content [string range $remain 1 [expr {$close_idx - 1}]]
            lappend result $content
        }

    # Trường hợp 2: list command [list …]
    } elseif {[string match {\[list *} $remain]} {
        set start [string first \[ $remain]
        set end   [string first \] $remain]
        if {$start != -1 && $end != -1 && $end > $start} {
            set inside [string range $remain [expr {$start + 6}] [expr {$end - 1}]]
            foreach item [split $inside] {
                lappend result $item
            }
        }

    # Trường hợp 3: concat [concat $var_a [list …] $var_b]
    } elseif {[string match {\[concat *} $remain]} {
        set start [string first \[ $remain]
        set end   [string first \] $remain]
        if {$start != -1 && $end != -1 && $end > $start} {
            set inside [string range $remain [expr {$start + 7}] [expr {$end - 1}]]
            foreach token [split $inside] {
                if {[string match {\$*} $token]} {
                    set varname [string range $token 1 end]
                    if {[dict exists $dict_var $varname]} {
                        foreach val [dict get $dict_var $varname] {
                            lappend result $val
                        }
                    }
                } elseif {[string match {\[list *} $token]} {
                    # Trích phần tử trong [list a b]
                    set inner_start [string first \[ $token]
                    set inner_end   [string first \] $token]
                    if {$inner_start != -1 && $inner_end != -1} {
                        set inner [string range $token [expr {$inner_start + 6}] [expr {$inner_end - 1}]]
                        foreach val [split $inner] {
                            lappend result $val
                        }
                    }
                } else {
                    lappend result $token
                }
            }
        }

    # Trường hợp 4: chỉ là text thường
    } else {
        set first_space [string first " " $remain]
        if {$first_space == -1} {
            lappend result $remain
        } else {
            set word [string range $remain 0 [expr {$first_space - 1}]]
            lappend result $word
        }
    }
    set clean_result {}
    foreach item $result {
        set item [string trim $item]
        if {$item eq ""} continue
        if {$item eq "list"} continue
        if {$item eq "\[list"} continue
        lappend clean_result $item
    }
    return $clean_result
}

# PROC 9: main parse view file
proc parse_view {filename} {
    set lines [debackslash_lines [read_entire_file $filename]]
    
    # 1. Parse biến dạng set var [list ...]
    set lib_var_dict [dict create]
    foreach line $lines {
        if {[regexp {^set\s+([^\s]+)\s+\[list\s+(.*)\]$} $line -> var values]} {
            set liblist [regexp -all -inline {\S+} $values]
            dict set lib_var_dict $var $liblist
        }
    }

    # 2. Parse tất cả command khác
    set libset_dict [dict create]
    set delaycorner_dict [dict create]
    set updatecorner_dict [dict create]
    set constraintmode_dict [dict create]
    set analysisview_dict [dict create]
    set meta_version 1.0
    foreach line $lines {
        # -- create_library_set -name ... -timing [concat ...]
        if {[string match "create_library_set*" $line]} {
            set toks [regexp -all -inline {\S+} $line]
            set idx_name [lsearch $toks "-name"]
            set idx_timing [lsearch $toks "-timing"]
            if {$idx_name >= 0 && $idx_timing >= 0} {
                set libset_name [lindex $toks [expr {$idx_name+1}]]
                set libs [extract_block_after_option_v2 $line "-timing" $lib_var_dict]
                dict set libset_dict $libset_name $libs
            }
            continue
        }
        # -- create_delay_corner -name ... -library_set ...
        if {[string match "create_delay_corner*" $line]} {
            set toks [regexp -all -inline {\S+} $line]
            set idx_name [lsearch $toks "-name"]
            set idx_libset [lsearch $toks "-library_set"]
            set idx_rc [lsearch $toks "-rc_corner"]
            if {$idx_name >= 0 && $idx_libset>= 0 && $idx_rc >= 0} {
                set delay_corner_name [lindex $toks [expr {$idx_name+1}]]
                set libset_name [lindex $toks [expr {$idx_libset+1}]]
                set rc_name [lindex $toks [expr {$idx_rc+1}]]
                dict set delaycorner_dict $delay_corner_name [list $libset_name $rc_name]
            }
            continue
        }
        # -- update_delay_corner -name ... -power_domain ... -library_set ...
        if {[string match "update_delay_corner*" $line]} {
            set toks [regexp -all -inline {\S+} $line]
            set idx_name [lsearch $toks "-name"]
            set idx_pd [lsearch $toks "-power_domain"]
            set idx_libset [lsearch $toks "-library_set"]
            if {$idx_name>=0 && $idx_pd>=0 && $idx_libset>=0} {
                set delay_corner_name [lindex $toks [expr {$idx_name+1}]]
                set pdomain [lindex $toks [expr {$idx_pd+1}]]
                set libset_name [lindex $toks [expr {$idx_libset+1}]]
                # Key kiểu "<delay_corner>|<power_domain>"
                dict set updatecorner_dict "${delay_corner_name}|${pdomain}" $libset_name
            }
            continue
        }
        # -- create_constraint_mode -name ... -sdc_files [list ...]
        if {[string match "create_constraint_mode*" $line]} {
            set toks [regexp -all -inline {\S+} $line]
            set idx_name [lsearch $toks "-name"]
            set idx_sdc [lsearch $toks "-sdc_files"]
            if {$idx_name>=0 && $idx_sdc>=0} {
                set cmode_name [lindex $toks [expr {$idx_name+1}]]
                set sdc_files [extract_block_after_option_v2 $line "-sdc_files" $lib_var_dict]
                dict set constraintmode_dict $cmode_name $sdc_files
            }
            continue
        }
        # -- create_analysis_view -name ... -constraint_mode ... -delay_corner ...
        if {[string match "create_analysis_view*" $line]} {
            set toks [regexp -all -inline {\S+} $line]
            set idx_name [lsearch $toks "-name"]
            set idx_cmode [lsearch $toks "-constraint_mode"]
            set idx_dly [lsearch $toks "-delay_corner"]
            if {$idx_name>=0 && $idx_cmode>=0 && $idx_dly>=0} {
                set view_name [lindex $toks [expr {$idx_name+1}]]
                set cmode_name [lindex $toks [expr {$idx_cmode+1}]]
                set dly_name [lindex $toks [expr {$idx_dly+1}]]
                dict set analysisview_dict $view_name [list $cmode_name $dly_name]
            }
            continue
        }
    }
# Return a dictionary which have neccessary dict for build_views_data
       return [dict create \
        libset_dict         $libset_dict \
        delaycorner_dict    $delaycorner_dict \
        updatecorner_dict   $updatecorner_dict \
        constraintmode_dict $constraintmode_dict \
        analysisview_dict   $analysisview_dict \
        meta_version        $meta_version]
}

# PROC 10: build up all parse data into 1 dict which have full information of each view.
proc build_views_data {libset_dict delaycorner_dict updatecorner_dict constraintmode_dict analysisview_dict upf_dict} {
    # Get the power domain data from the upf_dict
     if {[dict exists $upf_dict main_domains]} { set main_domains [dict get $upf_dict main_domains] } else { set main_domains {} }
     if {[dict exists $upf_dict normal_domains]} { set normal_domains [dict get $upf_dict normal_domains] } else { set normal_domains {} }
    #set main_domains [dict get $upf_dict main_domains]
    #set normal_domains [dict get $upf_dict normal_domains]

    # Initialize the global view dictionary
    set global_view_dict [dict create]

    # Loop through each view in analysisview_dict
    foreach view_name [dict keys $analysisview_dict] {
        # Extract view-specific data
        set view_data [dict get $analysisview_dict $view_name]
        set mode_name [lindex $view_data 0]  ;# constraint mode
        set delay_corner [lindex $view_data 1]  ;# delay_corner

        # Get RC corner and libset from delay_corner_dict
        set delay_info [dict get $delaycorner_dict $delay_corner]
        set libset_name [lindex [regexp -all -inline {\S+} $delay_info] 0]
        set rc_name [lindex [regexp -all -inline {\S+} $delay_info] 1]

        # Get SDC file from constraintmode_dict
        set sdc_files [dict get $constraintmode_dict $mode_name]

        # Initialize power domain mapping for this view
        set power_domains []

        # Loop through the updatecorner_dict to find power domains related to this delay_corner
        foreach update_key [dict keys $updatecorner_dict] {
            if {[string first "|" $update_key] >= 0} {
                # Key format: "<delay_corner>|<power_domain>"
                set tokens [split $update_key "|"]
                set update_delay_corner [lindex $tokens 0]
                set power_domain [lindex $tokens 1]

                if {$update_delay_corner eq $delay_corner} {
                    set update_libset [dict get $updatecorner_dict $update_key]
                    set domain_record [find_domain_mapping $power_domain $main_domains $normal_domains]
                    lappend power_domains [dict create \
                        domain_name [lindex $domain_record 0] \
                        domain_type [lindex $domain_record 1] \
                        instances [lindex $domain_record 2] \
                        libset_name $update_libset \
                        liblist [dict get $libset_dict $update_libset]]
                }
            }
        }

        # Add the data for this view to the global_view_dict
        dict set global_view_dict $view_name [dict create \
            mode_name $mode_name \
            sdc_files $sdc_files \
            delay_corner $delay_corner \
            rc_name $rc_name \
            power_domains $power_domains]
    }

    return $global_view_dict
}

# PROC 11: Helper proc to match power_domain to the correct main or normal domain
proc find_domain_mapping {power_domain main_domains normal_domains} {
    # Normalize power domain name for matching
    proc normalize_name {name} {
        set name [string trim $name]
        set name [string tolower $name]
        if {[string first "pd_" $name] == 0} {
            return [string range $name 3 end]
        }
        return $name
    }

    set normalized_name [normalize_name $power_domain]

    # Match against main domains
    foreach main $main_domains {
        set domain_name [lindex $main 0]
        if {[normalize_name $domain_name] eq $normalized_name} {
            return [list $domain_name "main" "ALL_INSTANCE"]
        }
    }

    # Match against normal domains
    foreach normal $normal_domains {
        set domain_name [lindex $normal 0]
        set supply [lindex $normal 1]
        set elements [lindex $normal 2]
        if {[normalize_name $domain_name] eq $normalized_name} {
            return [list $domain_name "normal" $elements]
        }
    }

    # If no match found
    return [list $power_domain "unknown" ""]
}

# PROC 12: print parse view note
proc print_parse_view_note {global_view_dict outfile } {
    # Open output file
    set fh [open $outfile "w"]

    # Print header
    puts $fh "====== View Parsing Note ======"
    puts $fh "Total views: [dict size $global_view_dict]"
    puts $fh ""

    # Process each view and print its number, name, and details
    set index 1
    foreach view_name [lsort -dictionary [dict keys $global_view_dict]] {
        set view_data [dict get $global_view_dict $view_name]

        # Header for each view
        puts $fh "# $index. View: $view_name"
        incr index

        # Print general info about the view
        puts $fh "  Constraint Mode: [dict get $view_data mode_name]"
        puts $fh "  SDC File(s): [join [dict get $view_data sdc_files] {, }]"
        puts $fh "  Delay Corner: [dict get $view_data delay_corner]"
        puts $fh "  RC Corner: [dict get $view_data rc_name]"

        # Print detailed info about power domains
        puts $fh "  Power Domains:"
        set power_domains [dict get $view_data power_domains]
        foreach pdomain $power_domains {
            puts $fh "    - Domain Name: [dict get $pdomain domain_name]"
            puts $fh "      Type: [dict get $pdomain domain_type]"
            puts $fh "      Instances: [join [dict get $pdomain instances] {, }]"
            puts $fh "      Lib Set Name: [dict get $pdomain libset_name]"
            puts $fh "      Libs: [join [dict get $pdomain liblist] {, }]"
        }
        puts $fh ""  ;# Add blank line for better readability
    }

    # Close the file handle
    close $fh
}

# write_lib_setting.tcl
# Generate a Tcl script `lib_setting.tcl` from `global_views_dict`.
# Format:
# - For main power domains: set_app_var link_path {* ...}
# - For normal power domains: set_app_var link_path_per_instance [list ...]

proc write_lib_setting {global_views_dict outfile} {
    # Open output file
    set fh [open $outfile "w"]

    # Write header
    puts $fh "#### Auto-generated lib setting script ####"
    puts $fh "# Total views: [dict size $global_views_dict]"
    puts $fh ""

    # Iterate through each view
    foreach view_name [lsort -dictionary [dict keys $global_views_dict]] {
        set view_data [dict get $global_views_dict $view_name]

        # Begin the if block for the current view
        puts $fh "if {\$VIEW eq \"$view_name\"} {"

        # Handle power domains
        set power_domains [dict get $view_data power_domains]
        set main_libs {}
        set normal_instances {}

        foreach pdomain $power_domains {
            set domain_type [dict get $pdomain domain_type]

            if {$domain_type eq "main"} {
                # Collect libs for main power domains
                set libs [dict get $pdomain liblist]
                foreach lib $libs {
                    lappend main_libs $lib
                }
            } elseif {$domain_type eq "normal"} {
                # Collect data for normal power domains
                set instances [dict get $pdomain instances]
                set libs [dict get $pdomain liblist]
                lappend normal_instances [list $instances $libs]
            }
        }

        # Write the main domain lib settings if any
        if {[llength $main_libs] > 0} {
            puts $fh "    set_app_var link_path {* \\"
            foreach lib $main_libs {
                puts $fh "        $lib \\"
            }
            puts $fh "    }"
        }

        # Write the normal domain lib settings if any
        if {[llength $normal_instances] > 0} {
            puts $fh "    set_app_var link_path_per_instance \[list \\"
            foreach inst_data $normal_instances {
                set instances [lindex $inst_data 0]
                set libs [lindex $inst_data 1]

                puts $fh "        \[list \\"
                puts $fh "            \[list \\"
                foreach instance $instances {
                    puts $fh "                $instance \\"
                }
                puts $fh "            ] \\"
                puts $fh "            {* \\"
                foreach lib $libs {
                    puts $fh "                $lib \\"
                }
                puts $fh "            } \\"
                puts $fh "        ] \\"
            }
            puts $fh "    ]"
        }

        # Close the if block for the current view
        puts $fh "}"
        puts $fh ""  ;# Blank line between views
    }

    # Close file handle
    close $fh
    puts "Lib setting script written to $outfile"
}


# ======= MAIN  =========
# 0.Configuration file
set UPF_FILE  "/ASIC3/users/hongquan_nguyen/scripts/01_flow/DEMO/ref.upf"
#set VIEW_FILE "/ASIC3/users/hongquan_nguyen/scripts/01_flow/DEMO/ref_view.tcl"
set VIEW_FILE "/ASIC3/users/hongquan_nguyen/scripts/01_flow/DEMO/viewDefinition.tcl"
set UPF_NOTE  "/ASIC3/users/hongquan_nguyen/scripts/01_flow/DEMO/upf_note.txt"
set VIEW_NOTE "/ASIC3/users/hongquan_nguyen/scripts/01_flow/DEMO/view_note.txt"
set LIB_FILE "/ASIC3/users/hongquan_nguyen/scripts/01_flow/DEMO/lib_setup.tcl"

# 1.Parse UPF to get main_domains and normal_domains
set upf_dict [parse_upf $UPF_FILE]
print_parse_upf_note $upf_dict $UPF_NOTE

# 2. Parse the view file
 set view_data_bundle [parse_view $VIEW_FILE]

# 3. Extract the relevant dicts from the results
set libset_dict [dict get $view_data_bundle libset_dict]
set delaycorner_dict [dict get $view_data_bundle delaycorner_dict]
set updatecorner_dict [dict get $view_data_bundle updatecorner_dict]
set constraintmode_dict [dict get $view_data_bundle constraintmode_dict]
set analysisview_dict [dict get $view_data_bundle analysisview_dict]

# 4. Build global view data
set global_view_dict [build_views_data $libset_dict $delaycorner_dict $updatecorner_dict $constraintmode_dict $analysisview_dict $upf_dict]

# 5. Print the view note
print_parse_view_note $global_view_dict $VIEW_NOTE

# 6. print data each view to each lib file setting
write_lib_setting $global_view_dict $LIB_FILE
