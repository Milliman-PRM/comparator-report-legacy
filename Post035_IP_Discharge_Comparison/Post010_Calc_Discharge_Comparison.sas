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
libname post035 "&post035.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/
/*Create the current and prior data sets summarized at the case level (Cases with a discharge only).*/
%Agg_Claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Time_Slice=&list_time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Dimensions=member_ID~caseadmitid~DischargeStatus
	,Force_Util=&post_force_util.
	,Where_Claims = %str(PRM_Discharges = 1)
	);

/*Merge the newly created table with the member roster table.  This will be the main table used for calculation of metrics.*/
proc sql;
	create table Discharge_cases_table as
	select 
		claims.*
	from agg_claims_med as claims 
	inner join 
		post008.members as mems 
		on claims.time_slice = mems.time_period 
		and claims.member_ID = mems.member_ID

	order by 
			claims.time_slice
			,claims.caseadmitid
	;
quit;

/*Calculate the requested measures.*/
proc sql;
	create table measures as
	select 
		"&name_client." as name_client
		,time_slice as time_period
		,"discharge_status" as metric_category

		,sum(case when DischargeStatus = "01" then 1 else 0 end)
			/count(caseAdmitID)
			as Discharge_home label="Discharged to Home"

		,sum(case when DischargeStatus IN ("62", "90") then 1 else 0 end)
			/count(caseAdmitID)
			as Discharge_irf label="Discharged to IRF"

		,sum(case when DischargeStatus = "03" then 1 else 0 end)
			/count(caseAdmitID)
			as Discharge_snf label="Discharged to SNF"

		,sum(case when DischargeStatus = "06" then 1 else 0 end)
			/count(caseAdmitID)
			as Discharge_homehlthcare label="Discharged to Home Health Care"

		,sum(case when DischargeStatus = "20" then 1 else 0 end)
			/count(caseAdmitID)
			as Discharge_died label="Died"

		,1.00 - calculated Discharge_home - calculated Discharge_irf - calculated Discharge_snf 
			- calculated Discharge_homehlthcare - calculated Discharge_died
			as Discharge_other label="Other"

		from Discharge_cases_table as cases
		group by
			name_client
			,time_period
			,metric_category
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
data post035.metrics_discharge_status;
	format &metrics_key_value_cgfrmt.;
	set metrics_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;
%LabelDataSet(post035.metrics_discharge_status)

%put return_code = &syscc.;
