/*
### CODE OWNERS: Shea Parkes

### OBJECTIVE:
	Get assignment information ready for client datamart.

### DEVELOPER NOTES:
	Need something just plausible enough.
		Assignment status credibility should be high.
		Assigned physician name should just have a plausible entry.
		Physician network status will just be sloppy at this time.
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

libname M015_Out "&M015_Out." access=readonly;
libname M017_Out "&M017_Out.";
libname M020_Out "&M020_Out." access=readonly; /*This is accessed out of "order"*/


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/



/**** MUNGE THE SHORT-CIRCUITED CLAIMS DATA ****/
proc sql noprint;
	select distinct quote(strip(Specialty))
	into :pcp_spec_codes separated by ','
	from M015_Out.Specialty_Names
	where upcase(Type) eq 'PCP'
	;
quit;
%put pcp_spec_codes = &pcp_spec_codes.;

data claims_slim;
	set M020_Out.CCLF5_PartB_Phys(keep = 
		clm_prvdr_spclty_cd
		clm_from_dt
		clm_thru_dt
		clm_idr_ld_dt
		bene_hic_num /*Not worth xref'ing for these limited purposes.*/
		clm_prvdr_tax_num
		rndrg_prvdr_npi_num
	);
	where clm_prvdr_spclty_cd in (&pcp_spec_codes.);
	format paid_month YYMMDDd10.;
	paid_month = intnx('month',clm_idr_ld_dt,0,'end');
run;

proc sql noprint;
	select max(paid_month)
	into :Date_LatestPaid trimmed
	from (
		select 
			paid_month
			,count(distinct bene_hic_num) as cnt_memid
		from claims_slim
		group by paid_month
		/*order by paid_month desc*/
		)
	where cnt_memid gt 42
	;
quit;

%put Date_LatestPaid = &Date_LatestPaid. %sysfunc(putn(&Date_LatestPaid.,YYMMDD10.));

proc sql;
	create table tin_to_npi_claims_dist as
	select
		clm_prvdr_tax_num as tin
		,rndrg_prvdr_npi_num as npi
		,count(distinct bene_hic_num) as cnt_memid
	from claims_slim
	group by
		clm_prvdr_tax_num
		,rndrg_prvdr_npi_num
	order by
		clm_prvdr_tax_num
		,cnt_memid desc
		,rndrg_prvdr_npi_num desc
	;
quit;

data tin_to_npi_claims;
	set tin_to_npi_claims_dist;
	by tin;
	if first.tin;
run;



/*** IMPUTE MISSING NPIs FROM ASSIGNMENT DATA ***/

proc sql;
	create table tin_to_npi_assign_dist as
	select
		tin
		,npi
		,count(distinct hicno) as cnt_memid
	from M017_Out.timeline_assign_extract
	where npi is not null
	group by
		tin
		,npi
	order by
		tin
		,cnt_memid desc
		,npi
	;
quit;

data tin_to_npi_assign;
	set tin_to_npi_assign_dist;
	by tin;
	if first.tin;
run;

proc sql;
	create table tin_to_npi_future_dist as
	select
		hicno
		,tin
		,npi
		,count(*) as cnt_records
	from M017_Out.timeline_assign_extract
	where npi is not null
	group by
		hicno
		,tin
		,npi
	order by
		hicno
		,tin
		,cnt_records desc
		,npi
	;
quit;

data tin_to_npi_future;
	set tin_to_npi_future_dist;
	by hicno tin;
	if first.tin;
run;

proc sql;
	create table assign_extract as
	select
		src.date_start
		,src.date_end
		,coalesce(xref.crnt_hic_num, src.hicno) as hicno format=$11. length=11
		,src.tin
		,coalesce(
			src.npi
			,npi_future.npi
			,npi_recurse.npi
			,npi_claims.npi
			/*,src.tin - Haven't gotten this desperate yet.*/
			) as npi format=$10. length=10
		/*,npi_future.npi as npi_future
		,npi_recurse.npi as npi_recurse
		,npi_claims.npi as npi_claims*/
	from M017_Out.timeline_assign_extract as src
	left join (
		select distinct crnt_hic_num, prvs_hic_num
		from M020_Out.CCLF9_bene_xref 
		)as xref on
		src.hicno eq xref.prvs_hic_num
	left join tin_to_npi_future as npi_future on
		src.hicno eq npi_future.hicno
		and src.tin eq npi_future.tin
	left join tin_to_npi_assign as npi_recurse on
		src.tin eq npi_recurse.tin
	left join tin_to_npi_claims as npi_claims on
		src.tin eq npi_claims.tin
	order by
		calculated hicno
		,src.date_end desc
		,src.date_start
	;
quit;
%AssertRecordCount(assign_extract,eq,%GetRecordCount(M017_Out.timeline_assign_extract),ReturnMessage=Table integrity was not maintained.)
%AssertNoNulls(assign_extract,npi,ReturnMessage=Not all assignments were resovled to an approximately useful NPI.)

/*
	TODO: Determine assigned NPI (not just TIN)

	From assignment: most common npi per tin
	From claims: most common npi per tin by claim count (PCP specialty claims only from cclf5_partb_phys only)
	Map NPIs onto TINs
	Fall back on TIN if have to and just make an entry in 
*/

/*
	TODO: Fill in non-assigned members.

	Fill in rest of members from CCLF8 with assignement_indicator = N
*/

/*
	TODO: Make timeline assignment.

	Break yearly assignment into quarters.  Last quarter is priority 3, rest are priority 1.
	Quarterly assignment gets priority 2.
	Then brake overlaps by priority.
	Extend oldest back to date_crediblestart.

	Extend the newest forwards to 2099
	Add a blanket underlying period of non-assigned for all members.
*/

/*
	TODO:

	Assume all the assigned NPIs are in-network (including the ones we inferred from TIN links in claims)
	Scrape the prv_names from NPI file just because it is required on client_physician
*/


%put System Return Code = &syscc.;
