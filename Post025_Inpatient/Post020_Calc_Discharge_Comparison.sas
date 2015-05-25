/*
### CODE OWNERS: Michael Menser, Aaron Hoch, Shea Parkes

### OBJECTIVE:
	This program creates a table with the individual metrics for IP Discharge Comparison.

### DEVELOPER NOTES:
	Calculate the requested measures using the inpatient table.
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname post025 "&post025.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/



proc sql;
	create table discharges_total as
	select 
		name_client
		,time_period
		,"discharge_status" as metric_category
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
	select distinct /*This distinct clause is needed. Without it, one line is output for every provider*/
		total.name_client as name_client
		,total.time_period as time_period
		,total.metric_category as metric_category
		,case when upcase(inpatient.discharge_status_desc) = "DISCHARGED TO HOME HEALTH CARE" 
				then "Home Health Care" 
			when upcase(inpatient.discharge_status_desc) = "UNKNOWN"
				then "Other"
			else scan(inpatient.discharge_status_desc,-1,' ') 
			end
			as metric_id format=$32. length=32
		,catx(" ","% of Inpatient Discharges with",calculated metric_id,"status") as metric_name
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
		,metric_id
		,metric_name
	;
quit;

data post025.metrics_discharge_status;
	format &metrics_key_value_cgfrmt.;
	set measures;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%LabelDataSet(post025.metrics_discharge_status)

%put return_code = &syscc.;
