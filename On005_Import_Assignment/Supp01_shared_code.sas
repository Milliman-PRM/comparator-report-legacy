/*
Client Code/Name: ACO / Accountable Care Options

Code Owners: Kyle Baird, Jack Leemhuis
*OWNERS ATTEST TO THE FOLLOWING:
  - The `master` branch will meet Milliman QRM standards at all times.
  - Deliveries will only be made from code in the `master` branch.
  - Review/Collaboration notes will be captured in Pull Requests (prior to merging).

  
Objective:
  Set up a location for code shared across multiple programs and modules to
  minimize duplication

Developer Notes:
  This is expected to be %included from a program that already has access to the
  normal PRM parameters
*/

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




%macro codegen_format_keep(name_datamart);
	proc datasets library = work nolist;
		delete __meta_data
			__meta_tables
			;
	quit;

	%include "&M008_cde.Func06_build_metadata_table.sas";

	%build_metadata_table(&name_datamart_src.
		,name_dset_out=__meta_data
		)

	proc sql;
		create table __meta_tables as
		select distinct
			name_table
		from __meta_data
		;
	quit;

	data _null_;
		set __meta_tables end = eof;
		format row_number $8.;
		row_number = strip(put(_n_,8.));
		call symputx(cats("name_table_",row_number),name_table,"L");
		if eof then call symputx("cnt_tables",row_number,"L");
	run;

	%do i_table = 1 %to &cnt_tables.;
		%let name_dset = &&name_table_&i_table..;

		%global 
			&name_dset._keep
			&name_dset._format
			;
		%let &name_dset._keep =;
		%let &name_dset._format =;
		proc sql noprint;
			select
				name_field
				,catx(" "
					,name_field
					,sas_format
					)
			into :&name_dset._keep separated by " "
				,:&name_dset._format separated by " "
			from __meta_data
			where upcase(name_table) eq "%upcase(&name_dset.)"
			;
		quit;
		%put &name_dset._keep = &&&name_dset._keep.;
		%put; *Write a blank line to the log to make tracer more readable.;
		%put &name_dset._format = &&&name_dset._format.;

		%let name_dset =;
	%end;

%mend codegen_format_keep;

/***** SAS SPECIFIC FOOTER SECTION *****/
%put System Return Code = &syscc.;
