/*
### CODE OWNERS: Shea Parkes

### OBJECTIVE:
	Generate "client datamart" files from CMS assignment information.

### DEVELOPER NOTES:
	Need something just plausible enough.
		Assignment status credibility should be high.
		Assigned physician name should just have a plausible entry.
		Physician network status will just be sloppy at this time.
	Potential future TODOs:
		Can apply actual MSSP assignment logic to claims data to choose individual NPIs.
		Couldn't get actual assignment info (Y/N) because ACO status of other NPIs is unknown.
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M008_cde.Func02_massage_windows.sas";

libname Ref_Prod "&Path_Product_Ref." access=readonly;
libname M015_Out "&M015_Out." access=readonly;
libname M017_Out "&M017_Out." access=readonly;
libname M018_Out "&M018_Out.";
libname M020_Out "&M020_Out." access=readonly; /*This is accessed out of "order"*/


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/



/*** CODEGEN FROM TARGET METADATA ***/

%build_metadata_table(
	references_client
	,name_dset_out=metadata_target
	)

%macro generate_codegen_variables(name_table);
	%global
		&name_table._fields_space
		&name_table._codegenformat
		;
	proc sql noprint;
		select
			name_field
			,catx(
				" "
				,name_field
				,sas_format
				)
		into :&name_table._fields_space separated by " "
			,:&name_table._codegenformat separated by " "
		from metadata_target
		where upcase(name_table) eq "%upcase(&name_table.)"
		;
	quit;
	%put &name_table._fields_space = &&&name_table._fields_space.;
	%put &name_table._codegenformat = &&&name_table._codegenformat.;
%mend generate_codegen_variables;

proc sql;
	create table tables_target as
	select distinct name_table
	from metadata_target
	;
quit;

data _null_;
	set tables_target;
	call execute(
		cats(
			'%nrstr(%generate_codegen_variables(name_table='
			,name_table
			,'))'
			)
		);
run;



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
	where rndrg_prvdr_npi_num is not null
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

proc sql;
	create table npi_dist_claims as
	select
		rndrg_prvdr_npi_num as npi
		,count(unique bene_hic_num) as npi_freq_claims
	from claims_slim
	where rndrg_prvdr_npi_num is not null
	group by npi
	order by npi_freq_claims desc
	;
quit;



/*** IMPUTE MISSING NPIs ON ASSIGNMENT DATA ***/

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
	create table npi_dist_assign as
	select
		npi
		,count(unique hicno) as npi_freq_assign
	from M017_Out.timeline_assign_extract
	where npi is not null
	group by npi
	order by npi_freq_assign desc
	;
quit;


proc sql;
	create table assign_extract as
	select
		inner.*
		,coalesce(npi_dist_claims.npi_freq_claims, 0) as npi_freq_claims
		,coalesce(npi_dist_assign.npi_freq_assign, 0) as npi_freq_assign
	from (
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
		) as inner
	left join npi_dist_assign on
		inner.npi eq npi_dist_assign.npi
	left join npi_dist_claims on
		inner.npi eq npi_dist_claims.npi
	order by
		inner.hicno
		,inner.date_end desc
		,inner.date_start
		,calculated npi_freq_assign desc
		,calculated npi_freq_claims desc
	;
quit;
%AssertRecordCount(assign_extract,eq,%GetRecordCount(M017_Out.timeline_assign_extract),ReturnMessage=Table integrity was not maintained.)
%AssertNoNulls(assign_extract,npi,ReturnMessage=Not all assignments were resovled to an approximately useful NPI.)



/*** AUTHOR CLIENT_PROVIDER AND CLIENT_FACILITY ***/

data M018_Out.Client_Facility;
	format &Client_Facility_CodegenFormat.;
	set _Null_;
	call missing(of _all_);
	label fac_net_hier_1 = 'ACO';
run;
%LabelDataSet(M018_Out.Client_Facility)

proc sql;
	create table npi_roster as
	select distinct npi
	from assign_extract
	union
	select distinct claims.npi
	from tin_to_npi_claims_dist as claims
	inner join (
		select distinct tin
		from assign_extract
		) as network_tins on
		claims.tin eq network_tins.tin
	order by npi
	;
quit;
%AssertNoDuplicates(npi_roster,npi,ReturnMessage=NPI Roster was not put together correctly.)

proc sort data=tin_to_npi_claims_dist out=npi_to_tin_claims_dist;
	by npi descending cnt_memid tin;
run;

data npi_to_tin_claims;
	set npi_to_tin_claims_dist;
	by npi;
	if first.npi;
run;

proc sort data=tin_to_npi_assign_dist out=npi_to_tin_assign_dist;
	by npi descending cnt_memid tin;
run;

data npi_to_tin_assign;
	set npi_to_tin_assign_dist;
	by npi;
	if first.npi;
run;

proc sql;
	create table npi_decorated as
	select
		src.npi as prv_id
		,case
			when npi.entity_type_cd eq "1" then case
				when npi.prvdr_credential_text is null then cat(propcase(strip(npi.prvdr_last_name)), ", ", propcase(strip(npi.prvdr_first_name)))
				else cat(propcase(strip(npi.prvdr_last_name)), " ", compress(npi.prvdr_credential_text,". "), ", ", propcase(strip(npi.prvdr_first_name)))
				end
			when npi.entity_type_cd eq "2" then propcase(coalescec(npi.prvdr_org_name, npi.prvdr_other_org_name, "Unknown"))
			else "Unknown"
			end as prv_name format=$128. length=128 label = 'ACO Provider'
		,case
			when tin_assign.tin is not null then catx(' ', 'Representative TIN:', tin_assign.tin)
			when tin_claims.tin is not null then catx(' ', 'Representative TIN:', tin_claims.tin)
			else 'Unknown'
			end as prv_hier_1 format=$128. length=128 label='Assigned Provider TIN'
	from npi_roster as src
	left join ref_prod.&filename_sas_npi. as npi on
		src.npi eq npi.npi
	left join npi_to_tin_assign as tin_assign on
		src.npi eq tin_assign.npi
	left join npi_to_tin_claims as tin_claims on
		src.npi eq tin_claims.npi
	order by src.npi
	;
quit;

proc sql noprint;
	select tgt.name_field
	into :providers_fields_lacking separated by ','
	from (
		select *
		from metadata_target
		where upcase(name_table) eq 'CLIENT_PROVIDER'
		) as tgt
	left join (
		select name
		from dictionary.columns
		where
			upcase(libname) eq 'WORK'
			and upcase(memname) eq 'NPI_DECORATED'
		) as thus_far on
		upcase(tgt.name_field) eq upcase(thus_far.name)
	where thus_far.name is null
	order by tgt.field_position
	;
quit;
%put providers_fields_lacking = &providers_fields_lacking.;

data M018_Out.Client_Provider;
	format &Client_Provider_CodeGenFormat.;
	set npi_decorated;
	call missing(&providers_fields_lacking.);

	prv_id_name = 'NPI';
	prv_net_hier_1 = 'ACO';
	label prv_net_hier_1 = 'ACO';
	prv_net_aco_yn = 'Y';
run;
%LabelDataSet(M018_Out.Client_Provider)


/*** FLESH OUT FULL TIMELINE INFORMATION ***/

proc sql noprint;
	select 
		max(date_end)
		,min(date_start)
	into
		:observed_end trimmed
		,:observed_start trimmed
	from assign_extract
	;
quit;
%put observed_end = &observed_end. %sysfunc(putn(&observed_end.,YYMMDD10.));
%put observed_start = &observed_start. %sysfunc(putn(&observed_start.,YYMMDD10.));

data assignment_broken_years;
	set assign_extract;

	format assignment_indicator $1.;
	assignment_indicator = 'Y';

	format priority 12.;
	/*
		Priority=0 will be a blanket "unassigned" action for all members.
		Priority=1 will be the first three quarters of a yearly assignment
		Priority=2 will be the quarterly periods
		Priority=3 will be the last quarter of a yearly assignment
		Extension periods will get the same priority as what they are extending.
	*/

	/*Bust up yearly assignments if we find them.*/
	if date_start eq intnx('month',date_end,-11,'beg') then do;
		date_end = intnx('month',date_end,-3,'end');
		priority = 1;
		output;
		date_start = date_end + 1;
		date_end = intnx('month',date_start,2,'end');
		priority = 3;
		output;
		end;
	else do;
		/*Assumed quarterly*/
		priority = 2;
		output;
		end;

run;

data assignment_extended_edges;
	format date_start date_end YYMMDDd10.;

	set assignment_broken_years(rename=(
		date_start = Preserve_Start
		date_end = Preserve_End
		));

	if &observed_end. lt &Date_LatestPaid. and Preserve_End eq &Observed_End. then do;
		date_start = Preserve_End + 1;
		date_end = &Date_LatestPaid.;
		output;
		end;

	if &observed_start. gt &Date_CredibleStart. and Preserve_Start eq &Observed_Start. then do;
		date_end = Preserve_Start - 1;
		date_start = &Date_CredibleStart.;
		output;
		end;

	drop Preserve_:;

run;

proc sql;
	create table assignment_latent_negation as
	select
		min(&Date_CredibleStart.,&Observed_Start.) as date_start format=YYMMDDd10.
		,max(&Date_LatestPaid.,&Observed_End.) as date_end format=YYMMDDd10.
		,src.hicno
		,'' as npi format=$10.
		,'' as tin format=$10.
		,'N' as assignment_indicator format=$1.
		,0 as priority format=12.
	from (
		select distinct bene_hic_num as hicno
		from M020_Out.CCLF8_Bene_Demog
		union
		select distinct hicno
		from assign_extract
		) as src
	order by hicno
	;
quit;

data assignment_all_priorities;
	set
		assignment_broken_years
		assignment_extended_edges
		assignment_latent_negation
		;
run;

%massage_windows(
	assignment_all_priorities
	,assignment_massaged
	,date_start
	,date_end
	,hicno
	,-priority~-npi_freq_assign~-npi_freq_claims~npi
	)



/*** MUNGE INTO FINAL FORMAT ***/

data M018_Out.Client_Member_Time;
	format &Client_Member_Time_CodeGenFormat.;

	set assignment_massaged(rename=(
		date_start = Sloppy_Start
		date_end = Sloppy_End
		hicno = member_id
		npi = mem_prv_id_align
		));

	Date_Start = Sloppy_Start;
	Date_End = min(intnx('month', Date_Start, 0, 'end'), Sloppy_End);
	output;

	do while (Date_End ne Sloppy_End);
	  Date_Start = Date_End + 1;
	  Date_End = min(intnx('month', Date_Start, 0, 'end'), Sloppy_End);
	  output;
	  end;

	label
		assignment_indicator = 'Assigned Patient'
		mem_prv_id_align = 'Assigned Provider'
		;
	
	keep &Client_Member_Time_Fields_Space.;
run;
%LabelDataSet(M018_Out.Client_Member_Time)

proc sql;
	create table client_member_prep as
	select
		src.*
		,coalesce(prv.prv_name,'Unknown') as mem_report_hier_2 format = $64. length=64 label='Assigned Provider (Hier)'
	from M018_Out.Client_Member_Time as src
	left join M018_Out.Client_Provider as prv on
		src.mem_prv_id_align eq prv.prv_id
	order by 
		src.member_id
		,src.date_end desc
	;
quit;

proc sql noprint;
	select tgt.name_field
	into :member_fields_lacking separated by ','
	from (
		select *
		from metadata_target
		where upcase(name_table) eq 'CLIENT_MEMBER'
		) as tgt
	left join (
		select name
		from dictionary.columns
		where
			upcase(libname) eq 'WORK'
			and upcase(memname) eq 'CLIENT_MEMBER_PREP'
		) as thus_far on
		upcase(tgt.name_field) eq upcase(thus_far.name)
	where thus_far.name is null
	order by tgt.field_position
	;
quit;
%put member_fields_lacking = &member_fields_lacking.;

data M018_Out.client_member;
	format &Client_Member_CodeGenFormat.;
	set client_member_prep;
	by member_id;
	if first.member_id;

	call missing(&member_fields_lacking.);

	mem_dependent_status = 'P';

	label mem_report_hier_1 = 'All Members (Hier)';
	mem_report_hier_1 = 'All';

	label mem_report_hier_3 = 'Not Implemented (Hier)';
	mem_report_hier_3 = 'Not Implemented';

	keep &Client_Member_Fields_Space.;
run;
%LabelDataSet(M018_Out.client_member)

%put System Return Code = &syscc.;
