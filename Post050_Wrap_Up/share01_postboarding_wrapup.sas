/*
### CODE OWNERS: Kyle Baird, Shea Parkes

### OBJECTIVE:
	Store code that is shared across programs in the module to limit
	duplication

### DEVELOPER NOTES:
	It is assumed that the IndyMacros and parser have been loaded.
*/

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




%macro sweep_for_sas_datasets(
	regex_table_name
	,name_dset_return=parsed_filenames
	);
	%GetFilenamesFromDir(
		Directory=&path_postboarding_data_root.
		,Output=__files_to_stack__
		,Keepstrings=.sas7bdat
		,subs=yes
		,types=files
		);

	data &name_dset_return. (drop=directory filename);
		set __files_to_stack__;
		format
			path_directory $2048.
			name_file $256.
			;
		path_directory = directory;
		name_file = scan(
			scan(filename,1,"\","B")
			,1
			,"."
			);
		if index(filename,"\") gt 0 then path_directory = cats(
			path_directory
			,substr(
				filename
				,1
				,find(
					filename
					,"\"
					,"i"
					,-length(filename)
					)
				)
			);
		%if %length(&regex_table_name.) gt 0 %then %do;
			if prxmatch(
				"&regex_table_name."
				,strip(name_file)
				)
				eq 0 then delete;
		%end;
	run;

	proc datasets library = work nolist;
		delete __files_to_stack__;
	quit;
%mend sweep_for_sas_datasets;



/**** SNAG LABELS FOR RE-USE ****/

libname temp035 "&M035_Out." access=readonly;

    proc sql noprint;
        select label
        into :lbl_elig_status_1 trimmed
        from dictionary.columns
        where
            upcase(libname) eq 'TEMP035'
            and upcase(memname) eq 'MEMBER'
            and upcase(name) eq 'ELIG_STATUS_1'
        ;
    quit;

    %put lbl_elig_status_1 = &lbl_elig_status_1.;

libname temp035 clear;


%put System Return Code = &syscc.;
