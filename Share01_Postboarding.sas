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

%let nonacute_ip_prm_line_ignore_snf = %str("i11b","i13a","i13b");
/*
	I11b Medical - Rehabilitation
	I13a Psychiatric - Hospital
	I13b Psychiatric - Residential
*/

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




/**** AGG_CLAIMS PARMATERS ****/

%let Post_Ongoing_Util_Basis = Discharge;
%let Post_Force_Util = N;

libname temp008 "&post008." access=readonly;

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
	from temp008.time_windows
	;
quit;
%put list_time_period = &list_time_period.;
%put list_inc_start = &list_inc_start.;
%put list_inc_end = &list_inc_end.;
%put list_paid_thru = &list_paid_thru.;

libname temp008 clear;



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

%put System Return Code = &syscc.;
