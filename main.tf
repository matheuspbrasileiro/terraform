# Aluno: Matheus Paulo Brasileiro
# Curso: MBA Full Stack Developer


terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

#CRIAR RESOURCE GROUP
resource "azurerm_resource_group" "rgmysql" {
    name     = "rgmysql"
    location = "eastus"

    tags     = {
        "Environment" = "atividade terraform"
    }
}

#CRIAR VIRTUAL NETWORK
resource "azurerm_virtual_network" "vnmysql" {
    name                = "vnmysql"
    address_space       = ["10.0.0.0/16"]
    location            = "eastus"
    resource_group_name = azurerm_resource_group.rgmysql.name
}

#CRIAR SUBNET
resource "azurerm_subnet" "subnetmysql" {
    name                 = "subnetmysql"
    resource_group_name  = azurerm_resource_group.rgmysql.name
    virtual_network_name = azurerm_virtual_network.vnmysql.name
    address_prefixes       = ["10.0.1.0/24"]
}

#CRIAR IP PUBLICO
resource "azurerm_public_ip" "publicipmysql" {
    name                         = "publicipmysql"
    location                     = "eastus"
    resource_group_name          = azurerm_resource_group.rgmysql.name
    allocation_method            = "Static"
}

#CRIAR NETWORK SECURITY GROUP - LIBERANDO AS PORTAS 3306 E 22
resource "azurerm_network_security_group" "nsgmysql" {
    name                = "nsgmysql"
    location            = "eastus"
    resource_group_name = azurerm_resource_group.rgmysql.name

    security_rule {
        name                       = "mysql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

#CRIAR NETWORK INTERFACE E CONFIGURACOES DE IP
resource "azurerm_network_interface" "nicmysql" {
    name                      = "nicmysql"
    location                  = "eastus"
    resource_group_name       = azurerm_resource_group.rgmysql.name

    ip_configuration {
        name                          = "myNicConfiguration"
        subnet_id                     = azurerm_subnet.subnetmysql.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.publicipmysql.id
    }
}
resource "azurerm_network_interface_security_group_association" "exampleAulaTerraform" {
    network_interface_id      = azurerm_network_interface.nicmysql.id
    network_security_group_id = azurerm_network_security_group.nsgmysql.id
}

data "azurerm_public_ip" "ip_data_db" {
  name                = azurerm_public_ip.publicipmysql.name
  resource_group_name = azurerm_resource_group.rgmysql.name
}

resource "azurerm_storage_account" "samsql" {
    name                        = "samsqls"
    resource_group_name         = azurerm_resource_group.rgmysql.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

#CRIANDO MAQUINA VIRTUAL
resource "azurerm_linux_virtual_machine" "vmmysql" {
    name                  = "vmmysql"
    location              = "eastus"
    resource_group_name   = azurerm_resource_group.rgmysql.name
    network_interface_ids = [azurerm_network_interface.nicmysql.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "myOsDiskMySQL"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "myvm"
    admin_username = "matheusteste"
    admin_password = "M@theus93"
    disable_password_authentication = false

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.samsql.primary_blob_endpoint
    }

    depends_on = [ azurerm_resource_group.rgmysql ]
}
output "public_ip_address_mysql" {
  value = azurerm_public_ip.publicipmysql.ip_address
}


resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.vmmysql]
  create_duration = "30s"
}

#UPLOAD DA PASTA CONFIG
resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = "matheusteste"
            password = "M@theus93"
            host = data.azurerm_public_ip.ip_data_db.ip_address
        }
        source = "config"
        destination = "/home/matheusteste"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

#INSTALACAO DO MYSQL
resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = "matheusteste"
            password = "M@theus93"
            host = data.azurerm_public_ip.ip_data_db.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/matheusteste/config/user.sql",
            "sudo cp -f /home/matheusteste/config/mysql.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}