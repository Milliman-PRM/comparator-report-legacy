/*
### CODE OWNERS: Brandon Patterson

### OBJECTIVE:
	Prepare a data dictionary describing the provided data to share
	with the client so they have information about the provided
	data to make it more useful to them.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
/*
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
*/

%let path_file_output = &post050.custom_report.xlsx;
%put path_file_output = &path_file_output.;

libname post050 "&post050." access=readonly;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


%build_metadata_table(
	_recursive_template
	,name_dset_out=metadata_recursive
	,_recursive_template_name_hook=_recursive_template
	)


data data_dictionary_recursive;
	set metadata_recursive (keep =
		name_field
		data_type
		data_size
		notes_client
		);
	where lowcase(name_field) in (
		"name_table"
		,"name_field"
		,"label"
		,"key_table"
		,"key_global"
		,"field_position"
		,"data_type"
		,"data_size"
		,"notes_client"
		);
	label
		name_field = "Field Name"
		data_type = "Data Type"
		data_size = "Data Size"
		notes_client = "Notes"
		;
run;

proc sql;
	create table data_dictionary_recursive_nodup as
	select distinct
		*
	from data_dictionary_recursive
	;
quit;

proc sql noprint;
	select distinct
		name_field
	into :meta_variables separated by " "
	from data_dictionary_recursive_nodup
	;
quit;
%put meta_variables = &meta_variables.;

proc sql;
	create table labels as
	select
		lowcase(memname) as name_table
		,lowcase(name) as name_field
		,label as label_observed
	from dictionary.columns
	where upcase(libname) eq "OUTPUTS"
		and label is not null
		and upcase(name) ne upcase(label) /*Ignore any unhelpful labels*/
	;
quit;

data data_dictionary_target;
	set metadata_target (keep = &meta_variables.);
	format label_observed $256.;
	if _n_ eq 1 then do;
		declare hash ht_labels (dataset: "labels", duplicate: "ERROR");
		ht_labels.definekey("name_table"
			,"name_field"
			);
		ht_labels.definedata("label_observed");
		ht_labels.definedone();

		call missing(label_observed);
	end;
	name_table = lowcase(name_table);
	name_field = lowcase(name_field);
	rc_labels = ht_labels.find();
	if rc_labels eq 0 then label = label_observed;
	drop rc_labels
		label_observed
		;
run;

proc sql;
	create table data_dictionary_recursive_order as
	select src.*
	from data_dictionary_recursive_nodup as src
	left join (
		select name, varnum
		from dictionary.columns
		where
			upcase(libname) eq 'WORK'
			and upcase(memname) eq 'DATA_DICTIONARY_TARGET'
		) as final_order on
	src.name_field eq final_order.name
	order by final_order.varnum
	;
quit;


proc export
	data = data_dictionary_recursive_order
	outfile = "&path_file_output."
	dbms = xlsx
	label
	replace
	;
	sheet = "Description";
run;

proc export
	data = data_dictionary_target
	outfile = "&path_file_output."
	dbms = xlsx
	replace
	;
	sheet = "Data Dictionary";
run;

%put System Return Code = &syscc.;
