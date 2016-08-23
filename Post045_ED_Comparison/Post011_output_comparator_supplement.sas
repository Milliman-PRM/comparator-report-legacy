/*
### CODE OWNERS: Brandon Patterson, Aaron Hoch
### OBJECTIVE:
	Output the data collected for a Caromont one-off report
### DEVELOPER NOTES:
	<none>
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;


%let path_file_output = &post045.comparator_supplement.xlsx;
%put path_file_output = &path_file_output.;

libname post010 "&post010." access=readonly;
libname post025 "&post025." access=readonly;
libname post045 "&post045." access=readonly;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


proc export
	data = post010.qtrly_drug_summary
	outfile = "&path_file_output."
	dbms = xlsx
	label
	replace
	;
	sheet = "Drug Summary";
run;


/*  Sanity Check for Heart Failure Data  */

proc summary nway missing data=Post025.Heart_failure_by_mem;
	class time_slice elig_status_1;
	var case_count;
	output out=custom_CHF_admits (drop=_:) sum=;
run;

data original_CHF_admits;
	set Post025.Metrics_inpatient;
	where metric_id = 'pqi08_admits';
run;

proc sql;
	create table Diffs_CHF_admits
	as select
		custom.*
		,orig.metric_value
	from custom_CHF_admits as custom
	inner join original_CHF_admits as orig
		on custom.time_slice = orig.time_period
		and custom.elig_status_1 = orig.elig_status_1
	where abs(orig.metric_value - custom.case_count) gt 2
	;
quit;

%AssertDataSetNotPopulated
	(
	diffs_CHF_admits
	,ReturnMessage = Member level results do not tie as closely as expected to Comparator Report for CHF admission counts
	)


/*  Export Heart Failure Data  */

proc export
	data = post025.heart_failure_by_mem
	outfile = "&path_file_output."
	dbms = xlsx
	label
	replace
	;
	sheet = "Heart Failure";
run;


/*  Sanity Check for ED data  */

proc summary nway missing data=Post045.Ed_prev_by_mem;
	class time_period elig_status_1;
	var ED_util ED_emer_pricare;
	output out=custom_ED_visits (drop=_:) sum=;
run;

data original_ED_preventable;
	set Post045.Metrics_er;
	where metric_id = 'ED_emer_pricare';
run;

proc sql;
	create table diffs_ED_preventable
	as select
		custom.time_period
		,custom.elig_status_1
		,round(custom.ED_emer_pricare, .001) as custom_preventable
		,round(orig_prev.metric_value, .001) as original_preventable

	from custom_ED_visits as custom
	inner join
		original_ED_preventable as orig_prev
		on custom.time_period = orig_prev.time_period
		and custom.elig_status_1 = orig_prev.elig_status_1
	where
		abs(calculated custom_preventable - calculated original_preventable) gt 2
	;
quit;

%AssertDataSetNotPopulated
	(
	diffs_ED_preventable
	,ReturnMessage = Member level results do not tie to Comparator Report for the # of ED visits
	)

/*  Export ED Data  */

proc export
	data = post045.ed_prev_by_mem
	outfile = "&path_file_output."
	dbms = xlsx
	label
	replace
	;
	sheet = "ED - PCP Treatable";
run;

%put System Return Code = &syscc.;
