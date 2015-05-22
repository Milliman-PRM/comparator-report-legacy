/*
### CODE OWNERS: Michael Menser 

### OBJECTIVE:
	This program creates a table with the individual metrics for IP Discharge Comparison.

### DEVELOPER NOTES:
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;

libname post008 "&post008." access = readonly;
libname post010 "&post010." access = readonly;
libname post025 "&post025.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Calculate the requested measures using the inpatient table.*/

/*Calculate the total discharges for each client, time period*/
proc sql;
	create table discharges_total as
	select 
		name_client
		,time_period
		,"IP Discharge" as metric_category
		,sum(cnt_discharges_inpatient) as total_discharges
	from Post025.details_inpatient
	group by 
		name_client
		,time_period
		,metric_category
	;
quit;

proc sql;
	create table measures as
	select distinct
		total.name_client as name_client
		,total.time_period as time_period
		,total.metric_category as metric_category
		,inpatient.discharge_status_desc as metric_name
		,sum(inpatient.cnt_discharges_inpatient)/total.total_discharges as metric_value
	from Post025.Details_inpatient as inpatient
	inner join 
		Discharges_total as total
		on inpatient.name_client = total.name_client
		and inpatient.time_period = total.time_period
	group by
		total.name_client
		,total.time_period
		,metric_category
		,inpatient.discharge_status_desc
	;
quit;

/*Transpose the dataset to get the data into a long format*/
proc transpose data=measures
		out=metrics_transpose(rename=(COL1 = metric_value))
		name=metric_id
		label=metric_name;
	by name_client time_period metric_category;
run;

/*Write the table out to the post035 library*/
data post035.metrics_IP_discharge;
	format &metrics_key_value_cgfrmt.;
	set metrics_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%put return_code = &syscc.;
