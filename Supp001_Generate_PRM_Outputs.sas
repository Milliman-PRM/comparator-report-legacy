/*
### CODE OWNERS: Aaron Burgess, Jason Altieri

### OBJECTIVE:
	Prepare a flatfile datamart for the client.

### DEVELOPER NOTES:
	<none>
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "&M008_Cde.Func03_Prv_Name_RegEx.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname NPI "&path_product_ref." access=readonly;
libname M015_Out "&M015_Out." access=readonly;
libname M020_Out "&M020_Out." access=readonly;
libname M025_Out "&M025_Out." access=readonly;
libname M035_Out "&M035_Out." access=readonly;
libname M073_Out "&M073_Out." access=readonly;
libname Post008 "&Post008." access=readonly;
libname Post070 "&Post070.";

%build_metadata_table(Flatfile_Report)

%macro CodeGen_Wrapper(name_table);
	%global _codegen_spaces_&name_table.;
	%global _codegen_format_&name_table.;
	proc sql noprint;
		select
			name_field
			,catx(" "
				,name_field
				,SAS_Format
				)
		into 
			:_codegen_spaces_&name_table. separated by " "
			,:_codegen_format_&name_table. separated by " "
		from meta_data
		where upcase(name_table) eq "%upcase(&name_table.)"
		;
	quit;
	%put _codegen_spaces_&name_table. = &&_codegen_spaces_&name_table..;
	%put _codegen_format_&name_table. = &&_codegen_format_&name_table..;

%mend CodeGen_Wrapper;

%CodeGen_Wrapper(memmos_elig);
%CodeGen_Wrapper(outclaims);
%CodeGen_Wrapper(outpharmacy);
%CodeGen_Wrapper(ref_prm_line);

proc sql noprint;
	select
		name
	into 
		:type_cds separated by ", "
	from dictionary.columns
	where libname = "NPI" and lowcase(memname) = "&Filename_SAS_NPI." and name like "other_prvdr_id_type_cd_%"
	;
quit;

%put &=type_cds.;

proc sql;
	create table npi_limit as
	select
		case when other_prvdr_id_type_cd_1 = '06' then other_prvdr_id_1
			when other_prvdr_id_type_cd_2 = '06' then other_prvdr_id_2
			when other_prvdr_id_type_cd_3 = '06' then other_prvdr_id_3
			when other_prvdr_id_type_cd_4 = '06' then other_prvdr_id_4
			when other_prvdr_id_type_cd_5 = '06' then other_prvdr_id_5
			when other_prvdr_id_type_cd_6 = '06' then other_prvdr_id_6
			when other_prvdr_id_type_cd_7 = '06' then other_prvdr_id_7
			when other_prvdr_id_type_cd_8 = '06' then other_prvdr_id_8
			when other_prvdr_id_type_cd_9 = '06' then other_prvdr_id_9
			when other_prvdr_id_type_cd_10 = '06' then other_prvdr_id_10
			when other_prvdr_id_type_cd_11 = '06' then other_prvdr_id_11
			when other_prvdr_id_type_cd_12 = '06' then other_prvdr_id_12
			when other_prvdr_id_type_cd_13 = '06' then other_prvdr_id_13
			when other_prvdr_id_type_cd_14 = '06' then other_prvdr_id_14
			when other_prvdr_id_type_cd_15 = '06' then other_prvdr_id_15
			when other_prvdr_id_type_cd_16 = '06' then other_prvdr_id_16
			when other_prvdr_id_type_cd_17 = '06' then other_prvdr_id_17
			when other_prvdr_id_type_cd_18 = '06' then other_prvdr_id_18
			when other_prvdr_id_type_cd_19 = '06' then other_prvdr_id_19
			when other_prvdr_id_type_cd_20 = '06' then other_prvdr_id_20
			when other_prvdr_id_type_cd_21 = '06' then other_prvdr_id_21
			when other_prvdr_id_type_cd_22 = '06' then other_prvdr_id_22
			when other_prvdr_id_type_cd_23 = '06' then other_prvdr_id_23
			when other_prvdr_id_type_cd_24 = '06' then other_prvdr_id_24
			when other_prvdr_id_type_cd_25 = '06' then other_prvdr_id_25
			when other_prvdr_id_type_cd_26 = '06' then other_prvdr_id_26
			when other_prvdr_id_type_cd_27 = '06' then other_prvdr_id_27
			when other_prvdr_id_type_cd_28 = '06' then other_prvdr_id_28
			when other_prvdr_id_type_cd_29 = '06' then other_prvdr_id_29
			when other_prvdr_id_type_cd_30 = '06' then other_prvdr_id_30
			when other_prvdr_id_type_cd_31 = '06' then other_prvdr_id_31
			when other_prvdr_id_type_cd_32 = '06' then other_prvdr_id_32
			when other_prvdr_id_type_cd_33 = '06' then other_prvdr_id_33
			when other_prvdr_id_type_cd_34 = '06' then other_prvdr_id_34
			when other_prvdr_id_type_cd_35 = '06' then other_prvdr_id_35
			when other_prvdr_id_type_cd_36 = '06' then other_prvdr_id_36
			when other_prvdr_id_type_cd_37 = '06' then other_prvdr_id_37
			when other_prvdr_id_type_cd_38 = '06' then other_prvdr_id_38
			when other_prvdr_id_type_cd_39 = '06' then other_prvdr_id_39
			when other_prvdr_id_type_cd_40 = '06' then other_prvdr_id_40
			when other_prvdr_id_type_cd_41 = '06' then other_prvdr_id_41
			when other_prvdr_id_type_cd_42 = '06' then other_prvdr_id_42
			when other_prvdr_id_type_cd_43 = '06' then other_prvdr_id_43
			when other_prvdr_id_type_cd_44 = '06' then other_prvdr_id_44
			when other_prvdr_id_type_cd_45 = '06' then other_prvdr_id_45
			when other_prvdr_id_type_cd_46 = '06' then other_prvdr_id_46
			when other_prvdr_id_type_cd_47 = '06' then other_prvdr_id_47
			when other_prvdr_id_type_cd_48 = '06' then other_prvdr_id_48
			else ''
		end as OSCAR,
		prvdr_org_name, 
		&type_cds.
	from NPI.&Filename_SAS_NPI. as npi
	where calculated OSCAR is not null
	order by OSCAR, prvdr_org_name
	;
quit;

proc transpose data=npi_limit out=npi_trans;
	by OSCAR prvdr_org_name;
	var other_prvdr_id_type_cd_:;
run;

proc sort data=npi_trans;
	by OSCAR prvdr_org_name _NAME_;
run;

data oscar_limit;
	set npi_trans;
	by OSCAR;

	if last.oscar then output;
run;

data propcase_names (drop = prvdr_org_name);
	set oscar_limit;

	%Prv_Name_RegEx(prvdr_org_name, prv_org_name);
run;

proc sql;
		create table outclaims_pre as
		select
			base.*
			,case when upcase(prm_util_type) = "DAYS" then prm_util else 0 end as prm_days
		from M073_Out.outclaims_prm as base
		left join propcase_names as pass
			on base.prm_prv_id_ccn eq pass.OSCAR
		order by sequencenumber
		;
quit;

%Assertthat(%GetRecordCount(outclaims_pre), eq, %GetRecordCount(M073_Out.outclaims_prm),ReturnMessage=Merging the provider organization name on is cartesianing the claims table)

data post070.outclaims (keep = &_codegen_spaces_outclaims. prm_prv_id_tin prm_prv_id_ccn prm_prv_id_attending prm_prv_id_operating);
	format &_codegen_format_outclaims.;
	set outclaims_pre;
run;

proc sql;
		create table outpharmacy_pre as
		select
			src.*
			,prv.prv_net_hier_1
		from M073_Out.Outpharmacy_prm as src
		left join M025_out.providers as prv
			on src.ProviderID eq prv.prv_id
		order by src.sequencenumber
		;
quit;

data post070.outpharmacy (keep = &_codegen_spaces_outpharmacy.);
	format &_codegen_format_outpharmacy.;
	set outpharmacy_pre;
	prv_net_hier_1 = coalescec(prv_net_hier_1, "OON");
run;

data post070.ref_prm_line (keep = &_codegen_spaces_ref_prm_line.);
	format &_codegen_format_ref_prm_line.;
    set M015_Out.mr_line_info;
	prm_line = mr_line;
	prm_line_category = prm_line_desc1;	
run;

proc sql;
	create table member_limit as 
	select mt.member_id
		  ,mt.elig_month
		  ,mt.elig_status_1
		  ,mt.Cover_Medical
		  ,mt.MemMos
		  ,mem.age
		  ,mem.gender
		  ,mem.mem_name
		  ,mem.mem_address_line_1
		  ,mem.mem_address_line_2
		  ,mem.mem_city_state
		  ,mem.mem_state
		  ,mem.mem_zip5
		  ,mem.dob
	from M035_out.member_time as mt
	left join M035_out.member as mem
		on mt.member_id = mem.member_id
	where upcase(mt.cover_medical) = "Y"
	order by member_id
	;
quit;

proc summary nway missing data = member_limit;
	class member_id elig_month elig_status_1 cover_medical
		  age gender mem_name mem_address_line_1 mem_address_line_2 mem_city_state mem_state mem_zip5 dob;
	var memmos;
output out = member_pre_summ (drop = _type_) sum=;
run;

data post070.memmos_elig (keep = &_codegen_spaces_memmos_elig.);
	format &_codegen_format_memmos_elig.;
	set member_pre_summ;
run;

%put System Return Code = &syscc.;
