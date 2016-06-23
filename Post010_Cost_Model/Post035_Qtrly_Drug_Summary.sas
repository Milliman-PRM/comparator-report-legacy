/*
### CODE OWNERS: Brandon Patterson

### OBJECTIVE:
	Generate a (one-off) quarterly summary of non-part-D drug use,
	tracking both utilization and costs

### DEVELOPER NOTES:
	Rx claims and eligibility will not be included because their
	costs are not available in the CCLF data
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname M015_Out "&M015_Out." access=readonly;
libname post008 "&post008." access=readonly;
libname post010 "&post010.";


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


/*  Currently hard-coded dates because the report is a one-off  */
%let time_slices = 2015Q4~2015Q3~2015Q2~2015Q1~2014Q4~2014Q3~2014Q2~2014Q1~2013Q4~2013Q3~2013Q2~2013Q1;
%let list_inc_start = 20362~20270~20179~20089~19997~19905~19814~19724~19632~19540~19449~19359;
%let list_inc_end = 20453~20361~20269~20178~20088~19996~19904~19813~19723~19631~19539~19448;
%let list_paid_thru = 20544~20453~20361~20269~20178~20088~19996~19904~19813~19723~19631~19539;


/***** GENERATE RAW SOURCE DATA *****/
%agg_claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Force_Util=&post_force_util.
	,Dimensions=HCPCS~mr_procs
	,Time_Slice=&time_slices.
	,Where_Claims=%str(Outclaims_PRM.PRM_Line in ("O16a", "O16b", "P34a", "P34b"))
	,Where_Elig=%str(member.assignment_indicator eq "Y")
	,Suffix_Output=drugs
	)

proc sql;
	create table qtrly_drug_costs as
	select
		"&name_client." as name_client
		,claims.time_slice as quarter
		,claims.HCPCS
		,description.hcpcs_desc
		,sum(mr_procs * rowcnt) as utilization
		,sum(prm_costs) as cost format dollar20.2
		,sum(prm_costs) / sum(mr_procs * rowcnt) as avg_cost format dollar20.2
		,sum(prm_costs) / qtr_total_cost as share_of_costs format percent10.4
	from
		Agg_claims_med_drugs as claims
	join
		(
		select time_slice, sum(prm_costs) as qtr_total_cost
		from agg_claims_med_drugs
		group by time_slice
		) as subtotal
	on claims.time_slice = subtotal.time_slice
	left join
		M015_Out.Hcpcs_descr as description
	on claims.hcpcs = description.hcpcs
	group by
		claims.time_slice
		,claims.HCPCS
	having
		sum(mr_procs * rowcnt) > 0
			or
		sum(prm_costs) > 0
	order by
		quarter desc
		,share_of_costs desc
	;
quit;

data post010.qtrly_drug_summary;
	set qtrly_drug_costs;
run;
%LabelDataSet(post010.qtrly_drug_summary);

%put System Return Code = &syscc.;
