# DNS records that Cloudflare creates and owns for other products. They are
# read only through the API, so Terraform forgets them instead of managing them.
#
# Workers custom domains: jono.miksu.app, turbodoc.miksu.app, t.miksu.link,
#   pluck.pics (AAAA 100::)
# Email Routing: pluck.pics MX route1-3.mx.cloudflare.net, and the
#   cf2024-1._domainkey DKIM TXT records for pluck.pics and siidorow.com

removed {
  from = cloudflare_dns_record.miksu_app_jono

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_dns_record.miksu_app_turbodoc

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_dns_record.miksu_link_t_aaaa

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_dns_record.pluck_pics_root_aaaa

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_dns_record.pluck_pics_mx_route1

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_dns_record.pluck_pics_mx_route2

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_dns_record.pluck_pics_mx_route3

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_dns_record.pluck_pics_dkim

  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_dns_record.siidorow_com_dkim

  lifecycle {
    destroy = false
  }
}
