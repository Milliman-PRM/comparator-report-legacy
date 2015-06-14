/*
### CODE OWNERS: Kyle Baird

### OBJECTIVE:
	Create client reference files for Pioneer ACOs

### DEVELOPER NOTES:
	Pioneer ACOs do not receive quarterly assignment files.  As such, we will
	attempt to assign providers to members using claims data.  At this point,
	our current needs to do not require exact assignment information.  Full CMS
	assignment logic was not implemented at this time.
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";

%AssertThat(
	%upcase(&cclf_exclusion_criteria.)
	,eq
	,PIONEER
	,ReturnMessage=Only applicable for Pioneer ACOs.
	,FailAction=endactivesassession
	)

/* Libnames */
libname ref_prod "&path_product_ref." access=readonly;
libname M015_Out "&M015_Out." access=readonly;
libname M020_Out "&M020_Out." access=readonly;
libname
	%sysfunc(ifc("%upcase(&project_id_prior.)" eq "NEW"
		,M035_out "&M035_out." /*If it is a warm start stacked member rosters will be seeded here*/
		,M035_old "&M035_old." /*Otherwise, grab from prior project*/
		))
	access=readonly
	;
libname M018_Out "&M018_Out.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




/*** MAKE A ROSTER OF MEMBERS WITH ASSIGNMENT INFORMATION ***/
proc sql noprint;
	select
		max(date_latestpaid) format = best12.
	into :max_date_latestpaid_history trimmed
	from
		%sysfunc(ifc("%upcase(&project_id_prior.)" eq "NEW"
			,M035_out.member_raw_stack_warm_start
			,M035_old.member_raw_stack
			))
	;
quit;
%put max_date_latestpaid_history = &max_date_latestpaid_history. %sysfunc(putn(&max_date_latestpaid_history.,YYMMDDd10.));

%setup_xref

data members_all;
	set %sysfunc(ifc("%upcase(&project_id_prior.)" eq "NEW"
		,M035_out.member_raw_stack_warm_start
		,M035_old.member_raw_stack
		))
		M020_out.cclf8_bene_demog (in = current_month)
		;
	*Make a ficticious date_latestpaid for the current month.
	Does not have to be accurate just accurate enough so we can
	distinguish most recent.;
	if current_month then date_latestpaid = %sysfunc(intnx(month,&max_date_latestpaid_history.,1,same));
	%use_xref(bene_hic_num,member_id)
	drop bene_hic_num;
run;

/*Attempt to back into who is assigned.*/
proc sql noprint;
	select
		count(distinct date_latestpaid)
		,min(date_latestpaid)
		,max(date_latestpaid)
	into :cnt_date_latestpaid trimmed
		,:min_date_latestpaid trimmed
		,:max_date_latestpaid trimmed
	from members_all
	;
quit;
%put cnt_date_latestpaid = &cnt_date_latestpaid.;
%put min_date_latestpaid = &min_date_latestpaid. %sysfunc(putn(&min_date_latestpaid.,YYMMDDd10.));
%put max_date_latestpaid = &max_date_latestpaid. %sysfunc(putn(&max_date_latestpaid.,YYMMDDd10.));

proc sql;
	create table member_aggregates as
	select
		member_id
		,count(distinct date_latestpaid) as cnt_date_latestpaid
		,min(date_latestpaid) as min_date_latestpaid format = YYMMDDd10.
		,max(date_latestpaid) as max_date_latestpaid format = YYMMDDd10.
	from members_all
	group by member_id
	order by member_id
	;
quit;

proc sql;
	create table member_deaths as
	select
		member_id
		,min(date_latestpaid) as death_date_latestpaid format = YYMMDDd10.
	from members_all
	where bene_death_dt is not null
	group by member_id
	order by member_id
	;
quit;

proc sort data = members_all
	out = members_all_sort
	;
	by
		member_id
		descending date_latestpaid
		;
run;

data members_basic;
	set members_all_sort (
		keep =
			member_id
			date_latestpaid
		);
	by
		member_id
		descending date_latestpaid
		;
	if first.member_id;

	mem_dependent_status = "P";

	label mem_report_hier_1 = "All Members (Hier)";
	mem_report_hier_1 = "All";
	label mem_report_hier_3 = "Not Implemented (Hier)";
	mem_report_hier_3 = "Not Implemented";
	drop date_latestpaid;
run;

data members;
	merge
		members_basic (in = member_roster)
		member_aggregates (in = dates)
		member_deaths (in = deaths)
		;
	by member_id;
	if member_roster;
	label assignment_indicator = "Assigned Patient";
	*Verbose here to explain different categories for assignment;
	if cnt_date_latestpaid eq &cnt_date_latestpaid. then assignment_indicator = "Y";
	else if max_date_latestpaid eq &max_date_latestpaid. then assignment_indicator = "Y"; *Opt-Ins are assigned, but not reported.;
	else if max_date_latestpaid ne &max_date_latestpaid. then do;
		if death_date_latestpaid ne . then assignment_indicator = "Y"; *If they no longer show up because of death, then assigned.;
		else assignment_indicator = "N"; *Opt-outs/excluded are not assigned. These are likely people included in the quarterly CMS excluded file.;
	end;
run;

/*** TAKE A GUESS AT WHO ARE OUR IN NETWORK PROVIDERS ***/
%let spec_codes_pcp = 
	"01"
	,"08"
	,"11"
	,"38"
	,"50"
	,"97"
	;

proc sql;
	create table claims_pcp_em as
	select
		coalesce(bene_xref.crnt_hic_num,base_claims.bene_hic_num) as member_id
		,base_claims.cur_clm_uniq_id
		,base_claims.clm_line_num
		,base_claims.clm_prvdr_spclty_cd
		,base_claims.clm_line_from_dt
		,base_claims.clm_line_thru_dt
		,base_claims.clm_line_hcpcs_cd
		,base_claims.clm_prvdr_tax_num
		,base_claims.rndrg_prvdr_npi_num
		,base_claims.clm_line_alowd_chrg_amt
	from M020_out.cclf5_partb_phys as base_claims
	inner join M015_out.cpt_em as ref_em
		on base_claims.clm_line_hcpcs_cd eq ref_em.em_cpt
	left join (
		select distinct
			crnt_hic_num
			,prvs_hic_num
		from M020_out.cclf9_bene_xref
		) as bene_xref
		on base_claims.bene_hic_num eq bene_xref.prvs_hic_num
	where base_claims.clm_prvdr_spclty_cd in (&spec_codes_pcp.)
	order by
		calculated member_id
		,base_claims.cur_clm_uniq_id
		,base_claims.clm_line_num
	;
quit;

proc sql;
	create table distinct_visits as
	select distinct
		member_id
		,rndrg_prvdr_npi_num
		,clm_line_thru_dt
		/*Do not worry about denied/reversed claims for our purposes, because we only care
		  that it happened, and who they were going to, not whether or not it was paid.*/
	from claims_pcp_em
	where rndrg_prvdr_npi_num is not null
	;
quit;

proc freq
	data = distinct_visits
	order = freq
	noprint
	;
	tables
		rndrg_prvdr_npi_num
		/ out = cummulative_percents
		outcum
		;
	attrib _all_ label = " ";
run;

proc sql noprint;
	select
		min(count)
	into :visit_cutoff trimmed
	from cummulative_percents
	where cum_pct le 60
	;
quit;
%put visit_cutoff = &visit_cutoff.;

proc sql;
	create table client_provider as
	select
		source_list.rndrg_prvdr_npi_num as prv_id
		,"NPI" as prv_id_name
		,"ACO" as prv_net_hier_1 label = "ACO"
		,"Y" as prv_net_aco_yn
		,case
			when npi.entity_type_cd eq "1" then case
				when npi.prvdr_credential_text is null then cat(propcase(strip(npi.prvdr_last_name)), ", ", propcase(strip(npi.prvdr_first_name)))
				else cat(propcase(strip(npi.prvdr_last_name)), " ", compress(npi.prvdr_credential_text,". "), ", ", propcase(strip(npi.prvdr_first_name)))
				end
			when npi.entity_type_cd eq "2" then propcase(coalescec(npi.prvdr_org_name, npi.prvdr_other_org_name, "Unknown"))
			else "Unknown"
			end as prv_name format=$128. length=128 label = 'ACO Provider'
		,taxonomy_desc.classification as prv_hier_1 label = "Provider Primary Specialty"
	from cummulative_percents as source_list
	left join ref_prod.&filename_sas_npi. as npi
		on source_list.rndrg_prvdr_npi_num eq npi.npi
	left join M015_out.prv_taxonomy_ref as taxonomy_desc
		on npi.health_prvdr_taxonomy_cd_1 eq taxonomy_desc.taxonomy_code
	where source_list.count ge &visit_cutoff.
	order by source_list.rndrg_prvdr_npi_num
	;
quit;

/*** ASSIGN MEMBERS TO PROVIDERS ***/
proc sql;
	create table member_em_visits as
	select
		distinct_visits.member_id
		,distinct_visits.rndrg_prvdr_npi_num
		,count(*) as cnt_visits
		,max(distinct_visits.clm_line_thru_dt) as recent_visit_date format = YYMMDDd10.
	from distinct_visits as distinct_visits
	inner join client_provider as prv_roster
		on distinct_visits.rndrg_prvdr_npi_num eq prv_roster.prv_id
	group by
		member_id
		,rndrg_prvdr_npi_num
	order by
		member_id
		,calculated cnt_visits desc
		,calculated recent_visit_date desc
	;
quit;

data member_providers_assigned;
	set member_em_visits;
	by
		member_id
		descending cnt_visits
		descending recent_visit_date
		;
	if first.member_id;
	keep
		member_id
		rndrg_prvdr_npi_num
		;
run;

proc sql;
	create table client_member as
	select
		members.*
		,case
			when upcase(members.assignment_indicator) eq "N" then "Unassigned"
			else coalesce(assigned.rndrg_prvdr_npi_num,"Unknown")
			end as mem_prv_id_align label = "Assigned Physician"
		,case
			when upcase(members.assignment_indicator) eq "N" then "Unassigned"
			else coalesce(prv.prv_name,"Unknown")
			end as mem_report_hier_2 length = 64 format = $64. label = "Assigned Physician (Hier)"
	from members as members
	left join member_providers_assigned as assigned
		on members.member_id eq assigned.member_id
	left join client_provider as prv
		on assigned.rndrg_prvdr_npi_num eq prv.prv_id
	order by members.member_id
	;
quit;

/*** MUNGE TO TARGET FORMATS ***/
%macro output(name_dset_source,name_dset_target);
	proc sql noprint;
		select
			catx(" ",name_field,sas_format)
			,name_field
		into :codegen_format separated by " "
			,:codegen_keep separated by " "
		from metadata_target
		where upcase(name_table) eq "%upcase(&name_dset_target.)"
		order by field_position
		;
	quit;
	%put codegen_keep = &codegen_keep.;
	%put codegen_keep = &codegen_keep.;

	proc sql noprint;
		select tgt.name_field
		into :fields_lacking separated by ','
		from (
			select *
			from metadata_target
			where upcase(name_table) eq "%upcase(&name_dset_target.)"
			) as tgt
		left join (
			select name
			from dictionary.columns
			where
				upcase(libname) eq 'WORK'
				and upcase(memname) eq "%upcase(&name_dset_source.)"
			) as thus_far on
			upcase(tgt.name_field) eq upcase(thus_far.name)
		where thus_far.name is null
		order by tgt.field_position
		;
	quit;
	%put fields_lacking = &fields_lacking.;

	data M018_out.&name_dset_target.;
		format &codegen_format.;
		set &name_dset_source.;
		call missing(&fields_lacking.);
		keep &codegen_keep.;
	run;
	%LabelDataSet(M018_out.&name_dset_target.)
%mend output;

%build_metadata_table(
	references_client
	,name_dset_out=metadata_target
	)

proc sql;
	create table dsets_target as
	select distinct
		name_table
	from metadata_target
	;
quit;

data _null_;
	set dsets_target;
	format
		name_dset_source $32.
		name_dset_target $32.
		;
	if exist(name_table) then name_dset_source = name_table;
	else name_dset_source = "_null_";
	name_dset_target = name_table;

	call execute(
		cats(
			'%nrstr(%output('
			,name_dset_source
			,','
			,name_dset_target
			,'))'
			)
		);
run;

%put System Return Code = &syscc.;
