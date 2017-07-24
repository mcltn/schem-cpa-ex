variable softlayer_username {}
variable softlayer_api_key {}
variable base_template_image {
  default = ""
}
variable datacenter {}
variable private_vlan {}
variable private_subnet {}
variable domain {}
variable domain_username {}
variable domain_password {}
variable dc_hostname {}
variable cn_hostname {}
variable computenode_count {}
variable domaincontroller_script_url {}

provider "ibm" {
  softlayer_username = "${var.softlayer_username}"
  softlayer_api_key = "${var.softlayer_api_key}"
}

data "ibm_compute_image_template" "base_template" {
  name = "${var.base_template_image}"
}

data "ibm_network_vlan" "private_vlan" {
  name = "${var.private_vlan}"
}

resource "ibm_compute_vm_instance" "domaincontroller" {
  count = "1"
  hostname = "${var.dc_hostname}"
  domain = "${var.domain}"
  image_id = "${data.ibm_compute_image_template.base_template.id}"
  datacenter = "${var.datacenter}"
  cores = 4
  memory = 4096
  network_speed = 1000
  local_disk = false
  private_network_only = false,
  private_vlan_id = "${data.ibm_network_vlan.private_vlan.id}"
  private_subnet = "${var.private_subnet}"
  hourly_billing = true,
  tags = ["schematics","domaincontroller"]
  user_metadata = <<EOF
    #ps1_sysnative
    script: |
    <powershell>
    New-Item c:\installs -type directory
    invoke-webrequest '${var.domaincontroller_script_url}' -outfile 'c:\installs\create-domain-controller.ps1'
    c:\installs\create-domain-controller.ps1 -domain ${var.domain} -username ${var.domain_username} -password ${var.domain_password} -step 1
    </powershell>
    EOF
}

resource "ibm_compute_vm_instance" "computenodes" {
  count = "${var.computenode_count}"
  hostname = "${var.cn_hostname}${count.index}"
  domain = "${var.domain}"
  image_id = "${data.ibm_compute_image_template.base_template.id}"
  datacenter = "${var.datacenter}"
  cores = 2
  memory = 2048
  network_speed = 1000
  local_disk = false
  private_network_only = true,
  private_vlan_id = "${data.ibm_network_vlan.private_vlan.id}"
  private_subnet = "${var.private_subnet}"
  hourly_billing = true,
  tags = ["schematics","compute"]
  user_metadata = <<EOF
    #ps1_sysnative
    script: |
    <powershell>
    New-Item c:\installs -type directory
    $ErrorActionPreference="SilentlyContinue"
    Stop-Transcript | out-null
    $ErrorActionPreference = "Continue"
    Start-Transcript -path C:\installs\output.txt -append
    $secure_string_pwd = ConvertTo-SecureString "${var.domain_password}" -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ("${var.domain_username}", $secure_string_pwd)
    $private_nic = Get-NetAdapter -Name "Ethernet 2"
    $private_nic | Set-DnsClientServerAddress -ServerAddresses ("${ibm_compute_vm_instance.domaincontroller.ipv4_address_private}")
    Sleep -Seconds 5
    Add-Computer -DomainName "${var.domain}" -Credential $cred
    Sleep -Seconds 5
    Stop-Transcript
    Restart-Computer
    </powershell>
    EOF
}
