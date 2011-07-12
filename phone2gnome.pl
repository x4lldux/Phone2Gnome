#!/usr/bin/perl -w
# phone2gnome.pl --- 
# Author: Pawel Drygas <x4lldux@jabster.pl>
# Created: 11 Jul 2011
# Version: 0.01

use warnings;
use strict;


use 5.010;
use strict;
use warnings;
use Switch;
use Data::Dumper;

use Glib qw/TRUE FALSE/;
use EV::Glib;
use Gtk2 "-init";
use EV;
use AnyEvent;

use Gtk2::Notify;
use Linux::Inotify2;
use JSON;
use Cwd;
use Regexp::Common qw /URI/;

use constant {
    APP_NAME => "Phone2Gnome",
    WATCHED_EVENTS => IN_CREATE|IN_MOVED_TO|IN_MODIFY,
};

my $inotify;

sub quit_cb {
   my ($widget, $status_icon) = @_;
 
   $status_icon->set_visible(0) if $status_icon;

   #Gtk2->main_quit();
   EV::unloop;
}

sub popup_menu_cb {
   my ($widget, $button, $time, $menu) = @_;

   if ($button == 3) {
       my ($x, $y, $push_in) = Gtk2::StatusIcon::position_menu($menu, $widget);
       $menu->show_all();
       $menu->popup( undef, undef,
             sub{return ($x,$y,0)} ,
             undef, 0, $time );
   }
}

sub activate_icon_cb {
   my $msgBox = Gtk2::MessageDialog->new(undef,
                     'GTK_DIALOG_MODAL',
                     'GTK_MESSAGE_INFO',
                     'GTK_BUTTONS_OK',
                     "Opens links and files shared from your Android phone.");
   $msgBox->run();
   $msgBox->destroy();
}

sub watch_dir {
    my $dir = shift;
    $inotify->watch ($dir, WATCHED_EVENTS, \&on_inotify_event);
}

sub on_inotify_event {
    my $e = shift;

    if ($e->name eq "pages") {
        open my $FH, "<", $e->fullname;
        my @json_txt=<$FH>;
        close $FH;
        $json_txt[0]="{\n";
        $json_txt[$#json_txt]='}';
        my $json_txt=join( "", @json_txt);
        my $pages=from_json ($json_txt, {utf8 => 1});

        my $last_site=scalar @{$pages->{pages}};
        my %page=%{$pages->{pages}->[$last_site-1]};
        if ($page{url}) {
            if ($page{url}=~/$RE{URI}{HTTP}/) {
                system ('xdg-open "'.$page{url}.'"');
                my $n = Gtk2::Notify->new(APP_NAME, 'Opening site "'.$page{title}.'".', getcwd."/phone2chrome.png");
                $n->show;
            } else {
                my $clipboard=Gtk2::Clipboard->get_for_display(Gtk2::Gdk::Display->open($ENV{'DISPLAY'}), Gtk2::Gdk->SELECTION_CLIPBOARD);
                $clipboard->set_text($page{url});
                
                my $n = Gtk2::Notify->new(APP_NAME, 'Text copied to clipboard.', getcwd."/phone2chrome.png");
                $n->show;
            }
        }
        
    }
    return;
}


sub init_ui {
    Gtk2::Notify->init(APP_NAME);
    
    our $status_icon = Gtk2::StatusIcon->new_from_file ("phone2gnome.png");
    our $menu = Gtk2::Menu->new();

    my $menuItem;
    $menuItem = Gtk2::ImageMenuItem->new_from_stock("gtk-about");
    $menuItem->signal_connect('activate', \&activate_icon_cb);
    $menu->append($menuItem);

    $menuItem = Gtk2::ImageMenuItem->new_from_stock('gtk-quit');
    $menuItem->signal_connect('activate', \&quit_cb, $status_icon);
    $menu->append($menuItem);

    $status_icon->set_tooltip(APP_NAME);
    $status_icon->signal_connect('activate', \&popup_menu_cb, $menu);
    $status_icon->signal_connect('popup-menu', \&popup_menu_cb, $menu);
    $status_icon->set_visible(1);
}


sub init_inotify {
    $inotify = Linux::Inotify2->new or die "Inotify, no joy!";
    our $io = AnyEvent->io (fh   => $inotify->fileno, poll => 'r', cb   => sub { $inotify->poll; });
    watch_dir $_[0];
}

init_inotify $ENV{HOME}."/Dropbox/phone2chrome/";
init_ui;

AnyEvent->loop;

for my $w (values %{$inotify->{w}}){
    $w->cancel;
}

1;
