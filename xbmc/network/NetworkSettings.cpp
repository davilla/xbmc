/*
 *      Copyright (C) 2005-2013 Team XBMC
 *      http://xbmc.org
 *
 *  This Program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2, or (at your option)
 *  any later version.
 *
 *  This Program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with XBMC; see the file COPYING.  If not, see
 *  <http://www.gnu.org/licenses/>.
 *
 */

#include "NetworkSettings.h"
#include "Application.h"

#include "guilib/GUIWindowManager.h"
#include "network/GUIDialogAccessPoints.h"
#include "settings/AdvancedSettings.h"
#include "settings/Setting.h"
#include "settings/Settings.h"
#include "utils/log.h"

CNetworkSettings::CNetworkSettings()
{
  CLog::Log(LOGDEBUG, "CNetworkSettings::CNetworkSettings");
}

CNetworkSettings::~CNetworkSettings()
{
}

CNetworkSettings& CNetworkSettings::Get()
{
  static CNetworkSettings sNetworkSettings;
  return sNetworkSettings;
}

void CNetworkSettings::OnSettingAction(const CSetting *setting)
{
  CLog::Log(LOGDEBUG, "CNetworkSettings::OnSettingAction");

  if (setting == NULL)
    return;

  const std::string &settingId = setting->GetId();
  if (settingId == "network.connection")
  {
    CGUIDialogAccessPoints *access_points = (CGUIDialogAccessPoints*)g_windowManager.GetWindow(WINDOW_DIALOG_ACCESS_POINTS);
    if (access_points)
    {
      access_points->DoModal();
      FillInNetworkConnection();
    }
  }
  else if (settingId == "network.apply")
  {
    CGUIDialogAccessPoints *access_points = (CGUIDialogAccessPoints*)g_windowManager.GetWindow(WINDOW_DIALOG_ACCESS_POINTS);
    if (access_points)
    {
      // fetch the connection name.
      std::string connection_name(((CSettingString*)setting)->GetValue());

      CIPConfig ipconfig;
      // fetch the current method
      ipconfig.m_method = CSettings::Get().GetInt("network.method") == 0 ? IP_CONFIG_DHCP:IP_CONFIG_STATIC;
      // fetch the current ip info
      ipconfig.m_address    = CSettings::Get().GetString("network.address");
      ipconfig.m_netmask    = CSettings::Get().GetString("network.netmask");
      ipconfig.m_gateway    = CSettings::Get().GetString("network.gateway");
      ipconfig.m_nameserver = CSettings::Get().GetString("network.nameserver");
      // pass the connection config as an encoded param string

      access_points->DoModal(WINDOW_DIALOG_ACCESS_POINTS, EncodeAccessPointParam(connection_name, ipconfig));
      FillInNetworkConnection();
    }
  }
}

void CNetworkSettings::FillInNetworkConnection()
{
  // run the net pump to clear out any stale info,
  // the water gets mighty dirty when the pump
  // only runs every 500ms.
  for (size_t i = 0; i < 20; i++)
    g_application.getNetwork().PumpNetworkEvents();

  std::string    name       = g_application.getNetwork().GetDefaultConnectionName();
  IPConfigMethod method     = g_application.getNetwork().GetDefaultConnectionMethod();
  std::string    address    = g_application.getNetwork().GetDefaultConnectionAddress();
  std::string    netmask    = g_application.getNetwork().GetDefaultConnectionNetmask();
  std::string    gateway    = g_application.getNetwork().GetDefaultConnectionGateway();
  std::string    nameserver = g_application.getNetwork().GetDefaultConnectionNameServer();

  // set method (dhcp or static)
  CSettings::Get().SetInt(   "network.method", method == IP_CONFIG_DHCP ? 0:1);

  // set network ip information
  CSettings::Get().SetString("network.connection",  name);
  CSettings::Get().SetString("network.address",     address);
  CSettings::Get().SetString("network.netmask",     netmask);
  CSettings::Get().SetString("network.gateway",     gateway);
  CSettings::Get().SetString("network.nameserver",  nameserver);

  CLog::Log(LOGDEBUG, "CNetworkSettings::FillInNetworkConnection-%s", name.c_str());
}


