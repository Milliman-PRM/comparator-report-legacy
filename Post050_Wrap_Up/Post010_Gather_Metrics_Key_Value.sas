/*
### CODE OWNERS: Jason Altieri, Aaron Hoch

### OBJECTIVE:
	Take the metrics and stack them together.

### DEVELOPER NOTES:

*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "%GetParentFolder(0)share01_postboarding_wrapup.sas" / source2;

/* Libnames */
libname Post050 "&Post050.";


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

%sweep_for_sas_datasets(%str(/^metrics_(?!key_value)/i))

/*** DERIVE A CONCATENTATED LIBRARY ***/
proc sql noprint;
	select distinct
		quote(strip(path_directory))
	into :libs separated by ","
	from parsed_filenames
	;
quit;
%put libs = &libs.;

libname Source (&libs.) access=readonly;

proc sql noprint;
	select cats("Source",".",name_file)
	into :files_stack separated by " "
	from parsed_filenames
	;
quit;
%put files_stack = &files_stack.;

/*** STACK RESULTS ***/
data Post050.metrics_key_value;
	format &metrics_key_value_cgfrmt.;
	label metric_ID= "Metric Identifier";
	label metric_name= "Metric Description";
	label elig_status_1 = "&lbl_elig_status_1.";
	set &files_stack.;
	keep &metrics_key_value_cgflds.;
run;
%LabelDataSet(Post050.metrics_key_value)

/*** VALIDATE OUTPUT CONTENTS (BEYOND STANDARD SCHEMA CHECKS) ***/
data metric_categories_expected;
	set metadata_target;
	where upcase(name_table) eq "METRICS_KEY_VALUE"
		and upcase(name_field) eq "METRIC_CATEGORY"
		;
	format metric_category $32.;
	do i_whitelist = 1 to countw(whitelist_nonnull_values,"~");
		metric_category = lowcase(scan(whitelist_nonnull_values,i_whitelist,"~"));
		output;
	end;
	keep metric_category;
run;

proc sort data = metric_categories_expected;
	by metric_category;
run;

proc sql;
	create table metric_categories_observed as
	select distinct
		lowcase(metric_category) as metric_category
	from post050.metrics_key_value
	order by metric_category
	;
quit;

data metric_category_mismatches;
	merge
		metric_categories_expected (in = expected)
		metric_categories_observed (in = observed)
		;
	by metric_category;
	format
		in_expected $1.
		in_observed $1.
		;
	if expected then in_expected = "Y";
	else in_expected = "N";
	if observed then in_observed = "Y";
	else in_observed = "N";
	if not(expected and observed);
run;
%AssertDataSetNotPopulated(
	metric_category_mismatches
	,ReturnMessage=%GetRecordCount(metric_category_mismatches) mismatches between expected and computed metric categories.
	)


proc summary nway missing data=post050.metrics_key_value;
	class name_client time_period elig_status_1 metric_ID;
	output out=chk_ID_dupes (drop= _type_);
run;

data _null_;
	set chk_ID_dupes;
	call %AssertThat(
					_freq_
					,eq
					,1
					,ReturnMessage=Metric_ID is not a unique identifier.
					)
					;

run;

proc summary nway missing data=post050.metrics_key_value;
	class name_client time_period elig_status_1 metric_name;
	output out=chk_name_dupes (drop= _type_);
run;

data _null_;
	set chk_name_dupes;
	call %AssertThat(
					_freq_
					,eq
					,1
					,ReturnMessage=Metric_name is not a unique identifier.
					)
					;

run;

%put System Return Code = &syscc.;
