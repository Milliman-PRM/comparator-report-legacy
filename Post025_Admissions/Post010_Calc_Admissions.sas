/*
### CODE OWNERS: Jason Altieri

### OBJECTIVE:
	Use the PRM outputs to create the Admissiion/Readmission report for NYP.

### DEVELOPER NOTES:
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";
%include "&M008_Cde.Func04_run_hcc_wrap_prm.sas";
%include "&M002_cde.supp01_validation_functions.sas";

/*Libnames*/
libname post008 "&post008.";
libname post025 "&post025.";

/*Create macro variables to be used in developing the metrics*/
proc sql noprint;
	select 
		time_period
		,inc_start format = 12.
		,inc_end format = 12.
		,paid_thru format = 12.
	into :time_period separated by "~"
		,:inc_start separated by "~"
		,:inc_end separated by "~"
		,:paid_thru separated by "~"
	from post008.Time_windows
	;
quit;

%put time_period = &time_period.;
%put inc_start = &inc_start.;
%put inc_end = &inc_end.;
%put paid_thru = &paid_thru.;

/*Used Ongoing_Util_Basis=Discharge and Force_Util=No to match the cost model program*/
/*Import inpatient claims excluding SNF for the "Current" time period*/
%agg_claims(
		IncStart=&inc_start.
		,IncEnd=&inc_end.
		,PaidThru=&paid_thru.
		,Med_Rx=Med
		,Ongoing_Util_Basis=Discharge
		,Force_Util=N
		,Dimensions=prm_line~caseadmitid~member_id~dischargestatus~providerID~prm_readmit_all_cause_yn~prm_ahrq_pqi
		,Time_Slice=&time_period.
		,Where_Claims=%str(substr(outclaims_prm.prm_line,1,1) eq "I" and outclaims_prm.prm_line ne "I31")
		,Where_Elig=
		,Date_DateTime=
		,Suffix_Output=
		)

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
		,a.time_slice as time_period
		,a.member_id
		,a.providerid as prv_id_inpatient
		,a.discharges
		,a.dischargestatus as discharge_status_code
		,a.prm_util as days
		,a.prm_util as los_inpatient
		,a.prm_costs as costs
		,a.prm_drg as drg_inpatient
		,a.prm_drgversion as drg_version_inpatient
		,(case when a.prm_line not in ('I11b', 'I13a', 'I13b') then 'Y' else 'N' end) as acute_yn
		,(case when a.prm_line in ('I11a', 'I11b') then 'Medical' 
			  when a.prm_line = 'I12' then 'Surgical' else 'N/A' end) as medical_surgical
		,a.prm_readmit_all_cause_yn as inpatient_readmit_yn
		,(case when a.prm_ahrq_pqi in('None', 'pqi02') then 'N' else 'Y' end) as inpatient_pqi_yn
		,'N' as preference_sensitive_yn
		,b.memmos
		,b.riskscr_1
	from agg_claims_med as a
	inner join post008.members as b on
		a.member_id = b.member_id and a.time_slice = b.time_period
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
	  acute_yn medical_surgical inpatient_pqi_yn preference_sensitive_yn inpatient_readmit_yn los_inpatient;
var discharges days costs memmos riskscr_1;
output out=details_inpatient (drop = _:)sum=cnt_discharges_inpatient sum_days_inpatient sum_costs_inpatient sum_memmos sum_riskscr;
run;

/*Calculate the requested measures*/
proc sql;
	create table measures as
	select
		name_client format $256.
		,time_period
		,"Admissions" as metric_category format $32.
		,sum(case when acute_yn = 'Y' then cnt_discharges_inpatient else 0 end)/sum(case when acute_yn = 'Y' then sum_memmos else 0 end)*12000 
			  as acute_per_1000 label="Acute Admits per 1000"
		,sum(case when acute_yn = 'Y' then cnt_discharges_inpatient else 0 end)/sum(case when acute_yn = 'Y' then sum_riskscr*sum_memmos else 0 end)*12000 
			  as acute_adj_1000 label="Acute Admits per 1000 Risk Adjusted"
		,sum(case when medical_surgical = 'Surgical' then cnt_discharges_inpatient else 0 end)/sum(case when medical_surgical = 'Surgical' then sum_memmos else 0 end)*12000 
			  as surg_per_1000 label="Surgical Admits per 1000"
		,sum(case when medical_surgical = 'Surgical' then cnt_discharges_inpatient else 0 end)/sum(case when medical_surgical = 'Surgical' then sum_riskscr*sum_memmos else 0 end)*12000 
			  as surg_adj_1000 label="Surgical Admits per 1000 Risk Adjusted"
		,sum(case when medical_surgical = 'Medical' then cnt_discharges_inpatient else 0 end)/sum(case when medical_surgical = 'Medical' then sum_memmos else 0 end)*12000
			  as med_per_1000 label="Medical Admits per 1000"
		,sum(case when medical_surgical = 'Medical' then cnt_discharges_inpatient else 0 end)/sum(case when medical_surgical = 'Medical' then sum_riskscr*sum_memmos else 0 end)*12000
			  as med_adj_1000 label="Medical Admits per 1000 Risk Adjusted"
		,sum(case when inpatient_pqi_yn = 'Y' then cnt_discharges_inpatient else 0 end)/sum(case when inpatient_pqi_yn = 'Y' then sum_memmos else 0 end)
			  as pqi label="PQI Combined (Chronic and Acute)"
		,sum(case when preference_sensitive_yn = 'Y' then cnt_discharges_inpatient else 0 end)/sum(case when preference_sensitive_yn = 'Y' then sum_memmos else 0 end)*12000
			  as pref_sens_per_1000 label="Preference Sensitive Admits per 1000"
		,sum(case when los_inpatient = 1 then cnt_discharges_inpatient else 0 end)/sum(cnt_discharges_inpatient)
			  as pct_1_day_LOS label="One Day LOS as a Percent of Total Admits"
		,sum(sum_costs_inpatient) as tot_acute_ccosts label="Total Acute Inpatient Costs"
	from details_inpatient
	group by time_period, name_client, metric_category
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
