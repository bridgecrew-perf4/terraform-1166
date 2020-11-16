# provider "aci" {
#       # cisco-aci user name
#       username = "apic:Local_Login_Domain\\\\bcs"
#       password = "bcs3.0Admin"
#       # cisco-aci url
#       url      =  "https://10.124.1.52"
#       insecure = true
# }
provider "aci" {
      # cisco-aci user name
      username = "admin"
      password = "ciscopsdt"
      # cisco-aci url
      url      =  "https://sandboxapicdc.cisco.com"
      insecure = true
}

locals {
    vlan_pools = {for i in csvdecode(file("vlan_pool.csv")): trimspace(i.name) => i if trimspace(i.name) != "" }
    vlan_encap_blocks = {for k,v in csvdecode(file("vlan_encap_block.csv")): "${trimspace(v.vlan_pool)}${k}" => v if trimspace(v.vlan_pool) != "" }
    domains = {for i in csvdecode(file("domain.csv")): trimspace(i.name) => i if trimspace(i.name) != "" }
    physical_domains = {for k,v in local.domains : k=>v if v.type == "physical" }
    vmm_vmware_domains = {for k,v in local.domains : k=>v if v.type == "vmm_vmware" }
    external_l3_domains = {for k,v in local.domains : k=>v if v.type == "external_l3" }
    external_l2_domains = {for k,v in local.domains : k=>v if v.type == "external_l2" }
    l2_ext_domain = "l2_ext_domain.json"
    aaeps = {for i in csvdecode(file("aaep.csv")): trimspace(i.name) => i if trimspace(i.name) != "" && i.enable_infra_vlan == "no" }
}

//vlan pool
resource "aci_vlan_pool" "vlan_pool" {
  for_each = local.vlan_pools
  name  = each.key
  alloc_mode  = trimspace(each.value.alloc_mode)
}
//vlan_encap_block
resource "aci_ranges" "vlan_encap_block" {
    for_each = local.vlan_encap_blocks

  vlan_pool_dn  = aci_vlan_pool.vlan_pool[each.value.vlan_pool].id

  _from  = "vlan-${each.value.start_vlan}"

  to  = "vlan-${each.value.stop_vlan}"
  alloc_mode  = each.value.alloc_mode
  role  = each.value.role
}
//physical domain
resource "aci_physical_domain" "phys_domain" {
    for_each = local.physical_domains
  name  = each.key
  relation_infra_rs_vlan_ns = aci_vlan_pool.vlan_pool[each.value.vlan_pool].id
}

//vmm domain place hoder <waiting for  provider_profile_dn >

//l3ext domain
resource "aci_l3_domain_profile" "l3_ext_domain" {
  for_each = local.external_l3_domains
  name  = each.key
  relation_infra_rs_vlan_ns = aci_vlan_pool.vlan_pool[each.value.vlan_pool].id
}
// l2ext domain is not support right now ,use aci_rest instead
resource "aci_rest" "l2_ext_domain" {
    for_each = local.external_l2_domains
  path       = "/api/node/mo/uni/l2dom-${each.key}.json"
  class_name = "l2extDomP"   // must specify class_name otherwise resource id is empty
   payload = templatefile(local.l2_ext_domain,{dn = "uni/l2dom-${each.key}", name = each.key , vlan_pool = aci_vlan_pool.vlan_pool[each.value.vlan_pool].id})
}

// create a itemidiate variable 
locals {
    all_domains = merge(aci_physical_domain.phys_domain, aci_l3_domain_profile.l3_ext_domain,aci_rest.l2_ext_domain)
} 
//aaep and its domain association .It doesn't support infrastructure vlan

    resource "aci_attachable_access_entity_profile" "aaep" {
        for_each = local.aaeps
        description = each.value.description
        name        = each.key
        relation_infra_rs_dom_p = [for i in split(" ",each.value.domain_name) : local.all_domains[i].id]
    }


output "aaeps" {
  value ={ for k ,v in aci_attachable_access_entity_profile.aaep : k=>v.id}
}

output "domains" {
  value = local.all_domains
}

