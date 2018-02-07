/*
### CODE OWNERS: Kyle Baird, Shea Parkes, Jason Altieri

### OBJECTIVE:
	Centralize postboarding code to avoid duplication.

### DEVELOPER NOTES:
	Likely intended to be %included() in most postboarding work.
	Intentionally left metadata_target in `work` library for potential downstream uses.
*/

/* DEVELOPMENT AID ONLY
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
*/
%include "&M008_cde.func06_build_metadata_table.sas";

%let name_datamart_target = Comparator_Report;

%let assign_name_client = name_client = "&name_client.";
%put assign_name_client = &assign_name_client.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




/**** AGG_CLAIMS PARMATERS ****/

%let Post_Ongoing_Util_Basis = Admit;
%let Post_Force_Util = N;

%Macro store_time_vectors(input_table= temp008.time_windows);

	libname temp008 "&post008." access=readonly;

	%IF %sysfunc(exist(&input_table.)) %THEN %DO;

		%global list_time_period;
		%global list_inc_start;
		%global list_inc_end;
		%global list_paid_thru;

		proc sql noprint;
			select
				time_period
				,inc_start format = best12.
				,inc_end format = best12.
				,paid_thru format = best12.
			into :list_time_period separated by "~"
				,:list_inc_start separated by "~"
				,:list_inc_end separated by "~"
				,:list_paid_thru separated by "~"
			from &input_table.
			;
		quit;
		%put list_time_period = &list_time_period.;
		%put list_inc_start = &list_inc_start.;
		%put list_inc_end = &list_inc_end.;
		%put list_paid_thru = &list_paid_thru.;

	%END;

	libname temp008 clear;

%Mend store_time_vectors;

%store_time_vectors()



/***** METADATA AND CODEGEN *****/

%build_metadata_table(
	&name_datamart_target.
	,name_dset_out=metadata_target
	)

%macro generate_codegen_variables(name_table);
	%global &name_table._cgflds
		&name_table._cgfrmt
		;
	proc sql noprint;
		select
			name_field
			,catx(
				" "
				,name_field
				,sas_format
				)
		into :&name_table._cgflds separated by " "
		,:&name_table._cgfrmt separated by " "
		from metadata_target
		where upcase(name_table) eq "%upcase(&name_table.)"
		;
	quit;
	%put &name_table._cgflds = &&&name_table._cgflds.;
	%put &name_table._cgfrmt = &&&name_table._cgfrmt.;
%mend generate_codegen_variables;
/*
%generate_codegen_variables(memmos)
*/

proc sql;
	create table tables_target as
	select distinct
		name_table
	from metadata_target
	;
quit;

data _null_;
	set tables_target;
	call execute(
		cats(
			'%nrstr(%generate_codegen_variables(name_table='
			,name_table
			,'))'
			)
		);
run;

proc sql;
	drop table tables_target;
quit;


%macro MakeMetaFields_custom(
	name_datamart
	,name_outdset
	,regex_memname_input
	,path_dir_datamart_root=&path_product_code.python\prm\meta\datamarts\
	);

	/*Derive the labels from the labels of the columns on the SAS data set.*/
	proc sql;
	  create table _dynamic_labels as select distinct
	  lowcase(name) as meta_field length = 32 format = $32. label = ""
	  ,label as meta_field_label label = ""
	  from dictionary.columns
	  where label is not null
	      and upcase(libname) net "SAS" /*Ignore SAS default libraries.*/
	  %if %length(&regex_memname_input.) gt 0 %then %do;
		  and prxmatch("&regex_memname_input.",strip(memname)) ne 0
	  %end;
	  ;
	quit;


	data &name_outdset. (keep = meta_field:)
	  	 _Label_DupCheck
	  ;
	  /*Infile the meta field data files.  Apply overrides to values based on parameters.*/
	  infile "&path_dir_datamart_root.\&name_datamart.\&name_datamart._Fields.csv" delimiter = "," dsd truncover lrecl = 10000 firstobs = 2;
	  input meta_field :$32. @;
	  *Combine the *_cat_ind and *_cat_lbl fields into one because they have duplicate labels
	   and should be represented as duals in QlikView.;
	  if index(upcase(meta_field),"_CAT_") > 0 then do;
		if scan(upcase(meta_field),1,"_","B") = "IND" then meta_field = substr(meta_field,1,length(meta_field) - 4);
		else delete;
	  end;
	  input
		meta_field_label :$80.
		date_type :$32.
		date_size :best12.
		allow_nulls :$1.
		whitelist_nonnull_values :$128.
		require_label_ifnotallnull :$1.
		notes_develop :$4096.
		meta_field_comment :$4096.
		;

	  meta_field = lowcase(meta_field);
	  if _n_ = 1 then do;
	    declare hash ht_dyn_labels (dataset:  "_dynamic_labels", duplicate: "ERROR");
	    rc = ht_dyn_labels.DefineKey("meta_field");
	    rc = ht_dyn_labels.DefineData("meta_field_label");
	    rc = ht_dyn_labels.DefineDone();
	  end;

	  rc_label = ht_dyn_labels.Find();

	  output &name_outdset.;
	  if meta_field_label ne "" then output _Label_DupCheck;
	run;
	%AssertNoDuplicates(_Label_DupCheck,meta_field_label,ReturnMessage=Duplicates labels found. See _Label_DupCheck table.)
	%LabelDataSet(&name_outdset.)

	data _false_labels;
		set _label_dupcheck;
		where upcase(meta_field) eq upcase(meta_field_label) and rc_label eq 0;
		run;
	%AssertDataSetNotPopulated(_false_labels,ReturnMessage=Label noise is coming through and can potentially disrupt QlikView.)

	%DeletePrivateDataSets()

%mend MakeMetaFields_custom;

%put System Return Code = &syscc.;
