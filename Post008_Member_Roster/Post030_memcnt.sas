/*
### CODE OWNERS: Michael Menser, Shea Parkes, Jason Altieri

### OBJECTIVE:
	Create the memcnt table from the member roster.

### DEVELOPER NOTES:
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";

libname M180_Out "&M180_Out." access=readonly;
libname post010 "&post010." access=readonly;
libname post008 "&post008.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


%agg_claims(
				IncStart=&list_inc_start.
				,IncEnd=&list_inc_end.
				,PaidThru=&list_paid_thru.
				,Ongoing_Util_Basis=&post_ongoing_util_basis.
				,Force_Util=&post_force_util.
				,Dimensions=member_id~dischargestatus~prm_todate
				,Time_Slice=&list_time_period.
				,Where_Claims=%str(upcase(outclaims_prm.prm_line) eqt "I" and lowcase(outclaims_prm.prm_line) ne "i31")
				)

	
/*Find the number of members for each combination of key variables (the memcnt table)*/
proc sql;
	create table memcnt_to_export as
	select
		"&name_client." as name_client
		,mems.time_period
		,mems.elig_status_1
		,case when decedents_w_time.member_id_excluded is not null then 'Y' else 'N' end as deceased_yn /*TODO: Append with Decedent/End of Life information when available*/ 
		,case when decedents_w_time.DischargeStatus eq '20' then "Y" else "N" end as deceased_hospital_yn
		,coalesce(decedents_w_time.endoflife_numer_yn_chemolt14days, 'N') as deceased_chemo_yn
		,coalesce(decedents_w_time.endoflife_numer_yn_hospicelt3day, 'N') as hospice_lt_3days
		,coalesce(decedents_w_time.endoflife_numer_yn_hospicenever,'N') as hospice_never
		,0 as final_hospice_days
		,coalesce(sum(decedents_w_time.prm_costs),0) as costs_final_30_days
		,count(*) as memcnt
	from post008.Members as mems
	left join (
			select
				claims.member_id
				,claims.time_slice as time_period
				,claims.PRM_Costs
				,claims.DischargeStatus
				,decedents.member_id_excluded
				,decedents.endoflife_numer_yn_chemolt14days
				,decedents.endoflife_numer_yn_hospicenever
				,decedents.endoflife_numer_yn_hospicelt3day
			from agg_claims_med as claims	/*To determine death from hospital and costs last 30 days*/
			inner join M180_Out.Puad12_member_excluded as decedents
				on claims.member_id = decedents.member_id_excluded
			where upcase(decedents.report_status_excluded) = "DEATH"
				and decedents.death_date_excluded - claims.prm_todate le 30
				) as decedents_w_time
		on mems.member_id = decedents_w_time.member_id_excluded 
		and mems.time_period = decedents_w_time.time_period
	group by mems.time_period
			,mems.elig_status_1
			,decedents_w_time.time_period
			,deceased_yn
			,deceased_hospital_yn
			,deceased_chemo_yn
			,hospice_lt_3days
			,hospice_never
			,final_hospice_days
			,decedents_w_time.member_id_excluded
			,decedents_w_time.endoflife_numer_yn_chemolt14days
			,decedents_w_time.endoflife_numer_yn_hospicelt3day
			,decedents_w_time.endoflife_numer_yn_hospicenever
	;
quit;

data post008.memcnt;
	format &memcnt_cgfrmt.;
	set memcnt_to_export;
	keep &memcnt_cgflds.;
run;

%LabelDataSet(post008.memcnt);

%put return_code = &syscc.;
