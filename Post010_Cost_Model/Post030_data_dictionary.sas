/*
### CODE OWNERS: Kyle Baird

### OBJECTIVE:
	Prepare a data dictionary describing the provided data to share
	with the client so they have information about the provided
	data to make it more useful to them.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "%GetParentFolder(0)supp010_shared_code.sas";
%include "&M008_cde.func06_build_metadata_table.sas";

%let path_file_output = &path_dir_outputs.Data Dictionary.xlsx;
%put path_file_output = &path_file_output.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




%build_metadata_table(
	&name_datamart_target.
	,name_dset_out=metadata_target
	)

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

data data_dictionary_target;
	set metadata_target (keep = &meta_variables.);
run;

proc export
	data = data_dictionary_recursive_nodup
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
