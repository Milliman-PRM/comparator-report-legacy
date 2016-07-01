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

%let months_runout_min = 3;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


/* Calculate custom quarterly time windows */
data time_windows;
	format
		time_period $8.
		inc_start
		inc_end
		paid_thru
		YYMMDDd10.
		;
	paid_thru = &Date_LatestPaid_Round.;
	inc_end = intnx('month', paid_thru, -&months_runout_min., 'end');
	/*Now round to nearest calendar quarter.*/
	inc_end = intnx('month', inc_end, -mod(month(inc_end), 3), 'end');
	inc_start = intnx('month', inc_end, -2, 'beg');
	time_period = cats(
		year(inc_start), 'Q', ceil(month(inc_start)/3)
		);
	output;
	do while(intnx('month', inc_start, -3, 'beg') ge &Date_CredibleStart.);
		paid_thru = intnx('month', paid_thru, -3, 'end');
		inc_end = intnx('month', inc_end, -3, 'end');
		inc_start = intnx('month', inc_start, -3, 'beg');
		time_period = cats(
			year(inc_start), 'Q', ceil(month(inc_start)/3)
			);
		output;
	end;
run;

proc sql noprint;
	select
		time_period
		,inc_start format best12.
		,inc_end format best12.
		,paid_thru format best12.
	into
		:time_slices separated by "~"
		,:list_inc_start separated by "~"
		,:list_inc_end separated by "~"
		,:list_paid_thru separated by "~"
	from Time_windows
	order by time_period desc;
quit;

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
	select distinct
		"&name_client." as name_client
		,claims.time_slice as quarter
		,claims.HCPCS
		,description.hcpcs_desc
		,sum(mr_procs * rowcnt) as utilization
		,sum(prm_costs) as cost format dollar20.2
		,calculated cost / sum(mr_procs * rowcnt) as avg_cost format dollar20.2
		,calculated cost / qtr_total_cost as share_of_costs format percent10.4
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
		,claims.hcpcs
	having
		calculated utilization > 0
			or
		calculated cost > 0
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
