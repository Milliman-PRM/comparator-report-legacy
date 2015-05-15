/*
### CODE OWNERS: Jason Altieri, Shea Parkes

### OBJECTIVE:
	Use the PRM outputs to create the Admissiion/Readmission report for NYP.

### DEVELOPER NOTES:
	Indend to create a "details" table and then individual metrics.
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";
%include "&M008_Cde.Func06_build_metadata_table.sas";
%include "&M002_cde.supp01_validation_functions.sas";

/*Libnames*/
libname post008 "&post008." access=readonly;
libname post025 "&post025.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

%agg_claims(
		IncStart=&list_inc_start.
		,IncEnd=&list_inc_end.
		,PaidThru=&list_paid_thru.
		,Med_Rx=Med
		,Ongoing_Util_Basis=&post_ongoing_util_basis.
		,Force_Util=&post_force_util.
		,Dimensions=prm_line~caseadmitid~member_id~dischargestatus~providerID~prm_readmit_all_cause_yn~prm_ahrq_pqi
		,Time_Slice=&list_time_period.
		,Where_Claims=
		,Where_Elig=
		,Date_DateTime=
		,Suffix_Output=
		)

proc sql;
	create table claims_members as
	select
		claims.*
	from agg_claims_med as claims
	inner join post008.members as mems
		on claims.Member_ID = mems.Member_ID and claims.time_slice = mems.time_period
	;
quit;

proc summary nway missing data=claims_members;
	class time_slice;
	var PRM_Costs;
	output out=costs_sum_all_services (drop=_:)sum=costs_sum_all_services;
run;

proc sql;
	create table mems_summary as
	select
		mems.time_period
		,sum(mems.memmos) as memmos_sum
		,sum(mems.riskscr_1*memmos) as tot_risk_scr
		,cost.costs_sum_all_services
	from post008.members as mems
	left join costs_sum_all_services as cost
		on mems.time_period = cost.time_slice
	group by time_period, costs_sum_all_services
	;
quit;

/*Limit acute IP stays by removing the following prm_lines:
	I11b--Medical - Rehabilitation
	I13a--Psychiatric - Hospital
	I13b--Psychiatric - Residential

	Exclude pqi02 from the count because it is not part of the composite PQI score.
*/
proc sql;
	create table claims_elig as
	select
		"&name_client." as name_client
		,time_slice as time_period
		,member_id
		,providerid as prv_id_inpatient
		,discharges
		,dischargestatus as discharge_status_code
		,prm_util as days
		,prm_util as los_inpatient
		,prm_costs as costs
		,prm_drg as drg_inpatient
		,prm_drgversion as drg_version_inpatient
		,(case when prm_line not in ('I11b', 'I13a', 'I13b') then 'Y' else 'N' end) as acute_yn
		,(case when prm_line in ('I11a', 'I11b') then 'Medical' 
			  when prm_line = 'I12' then 'Surgical' else 'N/A' end) as medical_surgical
		,prm_readmit_all_cause_yn as inpatient_readmit_yn
		,(case when prm_ahrq_pqi in('None', 'pqi02') then 'N' else 'Y' end) as inpatient_pqi_yn
		,(case when dischargestatus = '03' then 'Y' else 'N' end) as inpatient_discharge_to_snf_yn
		,'N' as preference_sensitive_yn
	from claims_members
	where %str(substr(prm_line,1,1) eq "I" and prm_line ne "I31")
	;
quit;

/*Add in discharge status description*/
data disch_xwalk;
	infile "%GetParentFolder(0)Discharge_status_xwalk.csv"
		lrecl=2048
		firstobs=2
		missover
		dsd
		delimiter=','
		;
	input
		disch_code :$2.
		disch_desc :$32.
		;
run;
	
proc sql;
	create table claims_w_desc as
	select
		claims.*
		,coalesce(xwalk.disch_desc,'Other') as discharge_status_desc format $256. 
	from claims_elig as claims
	left join disch_xwalk as xwalk on
		claims.discharge_status_code = xwalk.disch_code
	;
quit;

/*Aggreate the table to the datamart format*/
proc summary nway missing data=claims_w_desc;
class name_client time_period prv_id_inpatient discharge_status_code discharge_status_desc drg_inpatient drg_version_inpatient
	  acute_yn medical_surgical inpatient_pqi_yn preference_sensitive_yn inpatient_readmit_yn los_inpatient inpatient_discharge_to_snf_yn;
var discharges days costs;
output out=details_inpatient (drop = _:)sum=cnt_discharges_inpatient sum_days_inpatient sum_costs_inpatient;
run;

/*Calculate the requested measures*/
proc sql;
	create table measures as
	select
		detail.name_client
		,detail.time_period
		,"Admissions" as metric_category
		,sum(case when detail.acute_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)/mems.memmos_sum*12000 
			  as acute_per_1000 label="Acute Admits per 1000"
		,sum(case when detail.acute_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)/(mems.tot_risk_scr)*12000
			  as acute_adj_1000 label="Acute Admits per 1000 Risk Adjusted"
		,sum(case when detail.medical_surgical = 'Surgical' then detail.cnt_discharges_inpatient else 0 end)/mems.memmos_sum*12000 
			  as surg_per_1000 label="Surgical Admits per 1000"
		,sum(case when detail.medical_surgical = 'Surgical' then detail.cnt_discharges_inpatient else 0 end)/(mems.tot_risk_scr)*12000
			  as surg_adj_1000 label="Surgical Admits per 1000 Risk Adjusted"
		,sum(case when detail.medical_surgical = 'Medical' then detail.cnt_discharges_inpatient else 0 end)/mems.memmos_sum*12000
			  as med_per_1000 label="Medical Admits per 1000"
		,sum(case when detail.medical_surgical = 'Medical' then detail.cnt_discharges_inpatient else 0 end)/(mems.tot_risk_scr)*12000
			  as med_adj_1000 label="Medical Admits per 1000 Risk Adjusted"
		,sum(case when detail.inpatient_pqi_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)/mems.memmos_sum*12000
			  as pqi label="PQI Combined (Chronic and Acute)"
		,sum(case when detail.preference_sensitive_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)/mems.memmos_sum*12000
			  as pref_sens_per_1000 label="Preference Sensitive Admits per 1000"
		,sum(case when detail.los_inpatient = 1 then detail.cnt_discharges_inpatient else 0 end)/sum(detail.cnt_discharges_inpatient)
			  as pct_1_day_LOS label="One Day LOS as a Percent of Total Admits"
		,sum(detail.sum_costs_inpatient)/mems.costs_sum_all_services as pct_acute_IP_costs label="Acute Inpatient Costs as a Percentage of Total Costs"
		,sum(case when detail.inpatient_discharge_to_snf_yn = 'Y' then 1 else 0 end)/sum(detail.cnt_discharges_inpatient) as IP_to_SNF_pct label="Percentage of IP Stays Discharged to SNF"
	from details_inpatient as detail
	left join mems_summary as mems
		on detail.time_period = mems.time_period
	group by detail.time_period, detail.name_client, metric_category, mems.memmos_sum, mems.costs_sum_all_services, mems.tot_risk_scr
	;
quit;

/*Transpose the dataset to get the data into a long format*/
proc transpose data=measures 
				out=metrics_transpose(rename=(COL1 = metric_value))
				name=metric_id
				label=metric_name;
by name_client time_period metric_category;
run;

/*Codegen the output format for details_inpatient and metrics_key_value*/
data table_to_field;
	infile "%getparentfolder(1)\Post005_Datamarts\Comparator_Report\Comparator_Report_Tables.csv"
			lrecl=32767
			missover
			dsd
			firstobs=2
			delimiter=','
			;
	input
			name_field :$32.
			name_table :$32.
			key_table  :$1.
			key_global :$1.
			;
run; 

data target_formats;
	infile "%getparentfolder(1)\Post005_Datamarts\Comparator_Report\Comparator_Report_Fields.csv"
			lrecl=32767
			missover
			dsd
			firstobs=2
			delimiter=','
			;
	input
			name_field 					:$32.
			label      					:$32.
			data_type  					:$10.
			data_size  					:3.
			allow_nulls					:$1.
			whitelist_nonull_values		:$128.
			require_label_ifnotallnull  :$1.
			notes_develop				:$220.
			notes_client				:$220.
			;
	format SAS_Format SAS_Length $12.;
	select (upcase(data_type));
			when ("CHAR") SAS_Format = cats("$", put(data_size,12.),".");
			when ("VARCHAR") SAS_Format = cats("$", put(data_size,12.),".");
			otherwise SAS_Format = ".";
			end;

	SAS_Length = compress(SAS_Format, ".");
run; 

proc sql noprint;
	select 
		catx(" "
				,a.name_field
				,cats(" ",SAS_Length)
			)
		,catx(" "
				,a.name_field
				,cats(" ",SAS_Format)
			)
		into :details_length separated by " "
			,:details_format separated by " "
		from Target_formats as a
		left join table_to_field as b
			on a.name_field = b.name_field
		where upcase(b.name_table) eq "DETAILS_INPATIENT" and SAS_Format ne "."
	;
quit;
%put details_length = &details_length.;
%put details_format = &details_format.;

proc sql noprint;
	select 
		catx(" "
				,a.name_field
				,cats(" ",SAS_Length)
			)
		,catx(" "
				,a.name_field
				,cats(" ",SAS_Format)
			)
		into :metrics_length separated by " "
			,:metrics_format separated by " "
		from Target_formats as a
		left join table_to_field as b
			on a.name_field = b.name_field
		where upcase(b.name_table) eq "METRICS_KEY_VALUE" and SAS_Format ne "."
	;
quit;
%put metrics_length = &metrics_length.;
%put metrics_format = &metrics_format.;

data post025.details_inpatient;
length &details_length.;
set details_inpatient;
format &details_format.;
run;

/*Re-label the transposed variables with useful names and export*/
data post025.metrics_key_value;
length &metrics_length.;
set metrics_transpose;
format &metrics_format.;
label metric_id=metric_id metric_name=metric_name;
run;

%put return_code = &syscc.;
