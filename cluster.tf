
resource "rancher2_machine_config_v2" "nodes" {
  for_each      = var.node
  generate_name = replace(each.value.name, "_", "-")

  vsphere_config {
    cfgparam   = ["disk.enableUUID=TRUE"]
    clone_from      = var.vsphere_env.template
    cloud_config = templatefile("${path.cwd}/files/user_data_${each.key}.tftmpl",
      {
        pss_config     = file("${path.cwd}/files/pss-admission-config.yaml"),
        ssh_user       = "rancher",
        ssh_public_key = file("${path.cwd}/files/.ssh-public-key")
    }) # End of templatefile values

    creation_type   = "template"
    cpu_count       = each.value.vcpu
    datacenter      = var.vsphere_env.datacenter
    datastore       = var.vsphere_env.datastore
    disk_size       = each.value.hdd_capacity
    memory_size     = each.value.vram
    vcenter         = var.vsphere_env.server
  }
} # End of rancher2_machine_config_v2

resource "rancher2_cluster_v2" "rke2" {
  annotations        = var.rancher_env.cluster_annotations
  kubernetes_version = var.rancher_env.rke2_version
  labels             = var.rancher_env.cluster_labels
  name               = molmedocis

  rke_config {

    chart_values = <<EOF
      rke2-canal: {}
           
    EOF

    machine_global_config = <<EOF
      cni: canal
      kube-apiserver-arg: [ 
        "admission-control-config-file=/etc/rancher/rke2/rancher-deployment-pss.yaml"
      ]
    EOF

    dynamic "machine_pools" {
      for_each = var.node
      content {
        cloud_credential_secret_name = data.rancher2_cloud_credential.auth.id
        control_plane_role           = machine_pools.key == "ctl_plane" ? true : false
        etcd_role                    = machine_pools.key == "ctl_plane" ? true : false
        name                         = machine_pools.value.name
        quantity                     = machine_pools.value.quantity
        worker_role                  = machine_pools.key != "ctl_plane" ? true : false

        machine_config {
          kind = rancher2_machine_config_v2.nodes[machine_pools.key].kind
          name = replace(rancher2_machine_config_v2.nodes[machine_pools.key].name, "_", "-")
        }
      } # End of dynamic for_each content
    }   # End of machine_pools

    machine_selector_config {
     config = jsonencode({
        profile = "cis"
      })
  
    } # End machine_selector_config
  }   # End of rke_config
}   # End of rancher2_cluster_v2
