/*
### CODE OWNERS: Anna Chen, 

### OBJECTIVE:
	Calculate the Other Outpatient Metrics.  
    (See S:/PHI/NYP/Attachment A Core PACT Reports by Milliman for Premier.xlsx)

### DEVELOPER NOTES:
	According to CMS website, High-Tech Imaging includes CT, MRI and PET. 
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

libname post008 "&post008." access = readonly;
libname post010 "&post010." access = readonly;
libname post030 "&post030.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Store the start and end dates from the time windows dataset in variables for later use.*/
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
	from post008.Time_Windows
	;
quit;
%put time_period = &time_period.;
%put inc_start = &inc_start.;
%put inc_end = &inc_end.;
%put paid_thru = &paid_thru.;

/*Create the current and prior dataset with only the metrics that we need and with only eligible members using the function call;*/
%agg_claims(
		IncStart=&inc_start.
		,IncEnd=&inc_end.
		,PaidThru=&paid_thru.
		,Med_Rx=Med
		,Dimensions=prm_line~member_id~prm_ahrq_pqi
		,Time_Slice=&time_period.
		,Where_Claims=/*%str((substr(Outclaims_prm.prm_line,1,1) eq "O") or (Outclaims_prm.prm_line in ("P32c","P32d")))*/
		,Where_Elig=
		,Date_DateTime=
		,Suffix_Output=
		)

/*Created a claims_member summary table from merging in Post008.Members;*/
proc sql;
	create table claims_members as
	select
		claims.*
	   ,mems.riskscr_1
	from agg_claims_med as claims
	inner join post008.members as mems
		on claims.Member_ID = mems.Member_ID 
		and claims.time_slice = mems.time_period
	;
quit;

proc sql;
	create table mems_summary as
	select
		mems.time_period
		,sum(mems.memmos) as total_memmos
		,sum(mems.riskscr_1*memmos) as tot_risk_scr
	from post008.members as mems
	group by time_period
	;
quit;
	
/*Created a datail table for metrics calculation at the later process;*/ 
proc sql;
	create table claims_member_mod as
		select
			src.time_slice as time_period
			,"&name_client." as name_client
			,src.member_id
			,src.prm_line
			,src.prm_util

			,(case when src.prm_line in ("O14a","O14b","O14c") then "High_Tech_Imaging_Util" 
				   when src.prm_line = "O41h" then "Obs_Stays_Util"
				   when src.prm_line = "P32c" then "PCP_Office_Visits"
				   when src.prm_line = "P32d" then "Specialist_Office_Visit" else "N/A" end) as Util_Categ

			,(case when upcase(src.prm_ahrq_pqi) eq "NONE" or substr(src.prm_line,1,1) ne "O" then "N" else "Y" end) as outpatient_pqi_yn
			,(case when substr(src.prm_line,1,1) eq "O" then "Y" else "N" end) as outpatient_out_yn
			,(case when src.prm_line in ("P32c","P32d") then "Y" else "N" end) as outpatient_ov_yn

		 from claims_members as src
;
quit;

/*Aggreate the table to the datamart format*/
proc summary nway missing data=claims_member_mod;
class name_client time_period Util_Categ outpatient_pqi_yn outpatient_out_yn outpatient_ov_yn;
var prm_util;
output out=details_outpatient (drop = _:)sum=tot_util;
run;

/*Calculate the requested measures*/
proc sql;
	create table measures as
	select
		detail.name_client
		,detail.time_period
		,"OutPatient" as metric_category

		,sum(case when detail.outpatient_pqi_yn = 'Y' then detail.tot_util else 0 end)/mems.total_memmos*12000
		 	  as pqi label="PQI Combined (OutPatient)"

		,sum(case when detail.Util_Categ = "High_Tech_Imaging_Util" then detail.tot_util else 0 end)/mems.total_memmos*12000 
			  as HT_per_1000 label="High Tech Imaging Util per 1000"
		,sum(case when detail.Util_Categ = "High_Tech_Imaging_Util" then detail.tot_util else 0 end)/mems.tot_risk_scr*12000 
			  as HT_adj_1000 label="High Tech Imaging Util per 1000 Risk Adjusted"

		,sum(case when detail.Util_Categ = "Obs_Stays_Util" then detail.tot_util else 0 end)/mems.total_memmos*12000 
			  as Obs_per_1000 label="Observation Stays Util per 1000"
		,sum(case when detail.Util_Categ = "Obs_Stays_Util" then detail.tot_util else 0 end)/mems.tot_risk_scr*12000 
			  as Obs_adj_1000 label="Observation Stays Util per 1000 Risk Adjusted"

		,sum(case when detail.Util_Categ = "PCP_Office_Visits" then detail.tot_util else 0 end)/
		 sum(case when detail.outpatient_ov_yn = 'Y' then detail.tot_util else 0 end) 
			  as pct_pcp_visits label="Percentage PCP Office Visits"

	from details_outpatient as detail
	left join mems_summary as mems
		on detail.time_period = mems.time_period

	group by detail.time_period
			,detail.name_client
			,mems.total_memmos
			,mems.tot_risk_scr
	;
quit;

/*Munge to target formats*/
proc transpose data=measures 
				out=metrics_transpose(rename=(COL1 = metric_value))
				name=metric_id
				label=metric_name;
	by name_client time_period metric_category;
run;

/*data post030.details_outpatient;*/
/*	format &details_inpatient_cgfrmt.;*/
/*	set details_inpatient;*/
/*	keep &details_inpatient_cgflds.;*/
/*run;*/
/**/
/*data post030.metrics_outpatient;*/
/*	format &metrics_key_value_cgfrmt.;*/
/*	set metrics_transpose;*/
/*	keep &metrics_key_value_cgflds.;*/
/*	attrib _all_ label = ' ';*/
/*run;*/
