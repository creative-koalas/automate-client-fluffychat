#ifndef __Tray_H__
#define __Tray_H__

#include <gtk/gtk.h>
#if defined(APPINDICATOR_IS_AYATANA)
#if defined(__has_include)
#if __has_include(<libayatana-appindicator/app-indicator.h>)
#include <libayatana-appindicator/app-indicator.h>
#elif __has_include(<ayatana-appindicator/app-indicator.h>)
#include <ayatana-appindicator/app-indicator.h>
#else
#include <libayatana-appindicator/app-indicator.h>
#endif
#else
#include <libayatana-appindicator/app-indicator.h>
#endif
#else
#include <libappindicator/app-indicator.h>
#endif

typedef AppIndicator* (*app_indicator_new_fun)(const gchar*,
                                               const gchar*,
                                               AppIndicatorCategory);
typedef void (*app_indicator_set_status_fun)(AppIndicator*, AppIndicatorStatus);
typedef void (*app_indicator_set_icon_full_func)(AppIndicator* self,
                                                 const gchar* icon_name,
                                                 const gchar* icon_desc);
typedef void (*app_indicator_set_attention_icon_full_fun)(AppIndicator*,
                                                          const gchar*,
                                                          const gchar*);
typedef void (*app_indicator_set_menu_fun)(AppIndicator*, GtkMenu*);

class SystemTray {
 public:
  bool init_system_tray(const char* title,
                        const char* iconPath,
                        const char* toolTip);

  bool set_system_tray_info(const char* title,
                            const char* iconPath,
                            const char* toolTip);

  bool set_context_menu(GtkWidget* system_menu);

 protected:
  bool init_indicator_api();
  bool create_indicator(const char* title,
                        const char* iconPath,
                        const char* toolTip);

 protected:
  app_indicator_new_fun _app_indicator_new = nullptr;
  app_indicator_set_status_fun _app_indicator_set_status = nullptr;
  app_indicator_set_icon_full_func _app_indicator_set_icon_full = nullptr;
  app_indicator_set_attention_icon_full_fun
      _app_indicator_set_attention_icon_full = nullptr;
  app_indicator_set_menu_fun _app_indicator_set_menu = nullptr;

  AppIndicator* _app_indicator = nullptr;
};

#endif  // __Tray_H__
