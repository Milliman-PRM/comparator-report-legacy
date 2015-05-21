/*
### CODE OWNERS: Shea Parkes

### OBJECTIVE:
	Provide a framework to perform DRG case mix adjustments.

### DEVELOPER NOTES:
	Not part of production because it depends upon all ACOs' data being aggregated.
	For testing purposes, it case-mixes at the provider level.
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname post025 "&post025." access=readonly;

%let reporting_level = prv_id_inpatient; /*For development purposes.*/
*%let reporting_level = name_client;


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/





/**** STAGE DATA FOR ANALYSIS ****/

proc sql;
	create table full_agg as
	select
		&reporting_level.
		,discharge_status_desc
		,catx('_'
			,drg_inpatient
			,drg_version_inpatient
			) as drg format=$16. length=16
		,sum(cnt_discharges_inpatient) as discharges_sum format=comma12.
	from Post025.Details_Inpatient
	group by
		&reporting_level.
		,discharge_status_desc
		,drg
	order by
		&reporting_level.
		,discharge_status_desc
		,drg
	;
quit;

proc sql;
	create table eda_reporting_level as
	select
		&reporting_level.
		,sum(discharges_sum) as discharges_sum format=comma12.
	from full_agg
	group by &reporting_level.
	order by discharges_sum desc
	;
	create table eda_discharge_status_desc as
	select
		discharge_status_desc
		,sum(discharges_sum) as discharges_sum format=comma12.
	from full_agg
	group by discharge_status_desc
	order by discharges_sum desc
	;
quit;

proc sql;
	create table agg_filter as
	select agg.*
	from full_agg as agg
	inner join eda_reporting_level as eda on
		agg.&reporting_level. eq eda.&reporting_level.
	where 
		agg.discharges_sum gt 0
		/*This limit should only do something during testing/development.*/
		and eda.discharges_sum ge 142
	order by
		agg.&reporting_level.
		,agg.discharge_status_desc
		,agg.drg 
	;
quit;


%macro fit_one_status(
	name_dset_input
	,chosen_discharge_status
	,name_dset_output
	);

	data _munge_input;
		set &name_dset_input.;

		format cnt_success comma12.;
		if upcase(discharge_status_desc) eq "%upcase(&chosen_discharge_status.)" then cnt_success = discharges_sum;
		else cnt_success = 0;
	run;

	
	ods output lsmeans = &name_dset_output.;
	proc glimmix data=_munge_input method=laplace;
		class &reporting_level. drg;
		model cnt_success / discharges_sum = &reporting_level.;
		random drg;
		lsmeans &reporting_level. / ilink;
	run;
	ods output close;

	ods listing;

	proc sql;
		drop table _munge_input;
	quit;

%mend fit_one_status;

%fit_one_status(agg_filter,Discharged to Home,testing_ouput)


%put return_code = &syscc.;
