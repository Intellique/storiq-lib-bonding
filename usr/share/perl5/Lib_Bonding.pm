#!/usr/bin/perl
## ######### PROJECT NAME : ##########
##
## Lib_Bonding.pm for Lib_Bonding
##
## ######### PROJECT DESCRIPTION : ###
##
## This library is made for manage bond interfaces easily.
## Please use kernel version > 2.6.24.7
##
## ###################################
##
## Made by Boutonnet Alexandre
## Login   <aboutonnet@intellique.com>
##
## Started on  Thu Jun 19 18:03:00 2008 Boutonnet Alexandre
## Last update Tue Mar  3 15:45:28 2009 Boutonnet Alexandre
##
## ###################################
##

package Lib_Bonding;

# Declaration des Modules utilises
use strict;
use warnings;
use Data::Dumper;
use Lib_Network;

# Statics vars declaration
my $SYS_PATH         = '/sys/class/net/';
my $BOND_MASTER_FILE = 'bonding_masters';
my $MODE_FILE        = 'mode';
my $SLAVE_FILE       = 'slaves';
my $XMIT_FILE        = 'xmit_hash_policy';
my $ACTION_ADD       = '+';
my $ACTION_DEL       = '-';

# Errors hash
my $error_hash = {
    1 => 'Unable to open file : ',
    2 => ' is not a bonding interface.',
    3 => 'Invalid bonding mode',
    4 => ' : This mode is incompatible with xmit_hash_policy option.',
    5 => ' : This policy is incorrect.',
};

# Known modes
#    0 => balance-rr
#    1 => active-backup
#    2 => balance-xor
#    3 => broadcast
#    4 => 802.3ad
#    5 => balance-tlb
#    6 => balance-alb
my @mode_tab = (
    'balance-rr', 'active-backup', 'balance-xor', 'broadcast',
    '802.3ad',    'balance-tlb',   'balance-alb'
);

# Compatibles Modes with xmit_hash_policy
my @xmit_mode_tab = ( 'balance-xor', '802.3ad', );

# xmit_hash_policy policy values
my @xmit_values_tab = ( 'layer2', 'layer2+3', 'layer3+4', );

# Fonction qui recupere la liste des bonds actuellement PRESENTS au niveau NOYAU
# Cette fonction ne prend rien en parametre
# Elle retourne un tableau contenant la liste des bonds ou
# un tableau contenant un zero et un message d'erreur en cas d'echec
sub get_masters {
    my $return_tab;
    my $error_msg;

    ( $return_tab, $error_msg ) = _get_opt( $SYS_PATH . $BOND_MASTER_FILE );

    return ( $return_tab, $error_msg );
}

# Fonction d'ajout d'un bond.
# Cette fonction prend en parametre le nom de la nouvelle interface
# Le retour est un tableau contenant un bool (0 en cas de succes, et >0
# en cas d'echec) et une chaine de caractere contenant le message d'erreur.
# En cas de succes, le message d'erreur est vide
sub add_master {
    my ($name) = @_;
    my $return_tab;
    my $error_msg;

    return ( _add_opt( '', $BOND_MASTER_FILE, $name ) );
}

# Fonction de suppression d'un bond.
# Cette fonction prend en parametre le nom de l'interface
# Le retour est un tableau contenant un bool (0 en cas de succes, et >0
# en cas d'echec) et une chaine de caractere contenant le message d'erreur
# en cas de succes, le message d'erreur est vide
sub del_master {
    my ($name) = @_;
    my $return_tab;
    my $error_msg;

    return ( _del_opt( '', $BOND_MASTER_FILE, $name ) );
}

# Fonction de configuration du mode d'un bond.
# Cette fonction prend en parametre le nom du bond et le mode
# Le retour est un tableau contenant un bool (0 en cas de succes, et >0
# en cas d'echec) et une chaine de caractere contenant le message d'erreur
# en cas de succes, le message d'erreur est vide
sub set_mode {
    my ( $bond, $mode ) = @_;
    my $status_flag = 0;
    my $error;
    my $error_msg;

    # Je verifie si l'interface est un bond
    ( $error, $error_msg ) = _verify_bond($bond);
    return ( $error, $error_msg ) if ($error);

    # Correction du bug #336
    $mode = 4 if ( $mode =~ m/^802.3ad$/ );

    # Test si le mode est correct..
    ( $error, $error_msg ) = check_bond_mode($mode);
    return ( $error, $error_msg ) if ($error);

    # Si l'interface est up il faut l'arreter avant de modifier le mode
    if ( Lib_Network::get_if_status($bond) ) {
        $status_flag = 1;

        ( $error, $error_msg ) = Lib_Network::ifdown($bond);
        return ( $error, $error_msg ) if ($error);
    }

    ( $error, $error_msg ) = _set_opt( $bond, $MODE_FILE, $mode );

    # je dois re-up l'interface meme en cas d'erreur
    if ($status_flag) {
        my ( $tmp_error, $tmp_msg ) = Lib_Network::ifup($bond);
        if ($tmp_error) {
            return ( $tmp_error, $error_msg . ' + ' . $tmp_msg ) if ($error);
            return ( $tmp_error, $tmp_msg );
        }
    }

    return ( $error, $error_msg ) if ($error);

    return ( 0, '' );
}

# Fonction de recuperation du mode d'un bond
# Cette fonction prend en parametre :
# 1. Le nom du bond
# Le retour est un tableau contenant un bool (0) et un tableau contenant
# le nom du bond et le numero correspondant en cas de succes
# ou 1 et le message d'erreur en cas d'echec.
sub get_mode {
    my ($bond) = @_;

    # Je verifie si l'interface est un bond
    my ( $error, $error_msg ) = _verify_bond($bond);
    return ( $error, $error_msg ) if ($error);

    ( $error, $error_msg ) =
        _get_opt( $SYS_PATH . $bond . '/bonding/' . $MODE_FILE );

    return ( $error, $error_msg );
}

# Fonction d'ajout d'interface dans le bond
# Cette fonction prend un parametre :
# 1. Le nom du bond concerne
# 2. le nom de l'interface ou une reference sur un tableau contenant toutes les interfaces.
# Le retour est un tableau contenant un bool (0 en cas de succes, et >0
# en cas d'echec) et une chaine de caractere contenant le message d'erreur
# en cas de succes, le message d'erreur est vide
sub add_iface {
    my ( $bond, $iface ) = @_;
    my $error;
    my $error_msg;

    # Je verifie si le bond est correct
    ( $error, $error_msg ) = _verify_bond($bond);
    return ( $error, $error_msg ) if ($error);

    if ( ref($iface) eq 'ARRAY' ) {
        foreach my $eth ( @{$iface} ) {
            ( $error, $error_msg ) =
                _add_del_iface( $bond, $ACTION_ADD, $eth );
            return ( $error, $error_msg ) if ($error);
        }
    }
    else {
        ( $error, $error_msg ) = _add_del_iface( $bond, $ACTION_ADD, $iface );
        return ( $error, $error_msg ) if ($error);
    }

    return ( 0, '' );
}

# Fonction de suppression d'interface dans le bond
# Cette fonction prend un parametre :
# 1. Le nom du bond concerne
# 2. le nom de l'interface ou une reference sur un tableau contenant toutes les interfaces.
# Le retour est un tableau contenant un bool (0 en cas de succes, et >0
# en cas d'echec) et une chaine de caractere contenant le message d'erreur
# en cas de succes, le message d'erreur est vide
sub del_iface {
    my ( $bond, $iface ) = @_;
    my $error;
    my $error_msg;

    # Je verifie si le bond est correct
    ( $error, $error_msg ) = _verify_bond($bond);
    return ( $error, $error_msg ) if ($error);

    if ( ref($iface) eq 'ARRAY' ) {
        foreach my $eth ( @{$iface} ) {
            ( $error, $error_msg ) =
                _add_del_iface( $bond, $ACTION_DEL, $eth );
            return ( $error, $error_msg ) if ($error);
        }
    }
    else {
        ( $error, $error_msg ) = _add_del_iface( $bond, $ACTION_DEL, $iface );
        return ( $error, $error_msg ) if ($error);
    }

    return ( 0, '' );
}

# Fonction de recuperation des interfaces presentes
# dans un bond
# Cette fonction prend en parametre le nom du bond
# Le retour est un tableau contenant 0 et un tableau contenant les interfaces
# en cas de succes. En cas d'echec, le tableau contient un code d'erreur
# et un message..
sub get_iface {
    my ($bond) = @_;

    # Je verifie si l'interface est un bond
    my ( $error, $error_msg ) = _verify_bond($bond);
    return ( $error, $error_msg ) if ($error);

    return ( _get_opt( $SYS_PATH . $bond . '/bonding/' . $SLAVE_FILE ) );
}

# Fonction de configuration d'une option
# Cette fonction prend en parametre :
# 1. Le nom du bond
# 2. Le nom de l'option
# 3. La valeur
# Le retour est un tableau contenant un bool (0 en cas de succes, et >0
# en cas d'echec) et une chaine de caractere contenant le message d'erreur
# en cas de succes, le message d'erreur est vide
sub set_option {
    my ( $bond, $option, $value ) = @_;
    my $error;
    my $error_msg;

    # Je verifie si le bond est correct
    ( $error, $error_msg ) = _verify_bond($bond);
    return ( $error, $error_msg ) if ($error);

    ( $error, $error_msg ) = _set_opt( $bond, $option, $value );
    return ( $error, $error_msg ) if ($error);

    return ( 0, '' );
}

# Fonction de configuration de l'option xmit_hash_policy
# Cette fonction prend en parametre :
# 1. Le nom du bond
# 2. La valeur de xmit_hash_policy
# Le retour est un tableau contenant un bool (0 en cas de succes, et >0
# en cas d'echec) et une chaine de caractere contenant le message d'erreur
# en cas de succes, le message d'erreur est vide
sub set_xmit_hash_policy {
    my ( $bond, $value ) = @_;
    my $error;
    my $error_msg;
    my $status_flag = 0;

    # Je verifie si le bond est correct
    ( $error, $error_msg ) = _verify_bond($bond);
    return ( $error, $error_msg ) if ($error);

    # Je recupere le mode du bonding actuel.
    my $opt  = _get_opt( $SYS_PATH . $bond . '/bonding/' . $MODE_FILE );
    my $mode = @{$opt}[0];

    # Verification de la compatibilite du bond
    return ( 1, $mode . $error_hash->{4} )
        if ( !grep( /^$mode$/, @xmit_mode_tab ) );

    my $tmp_value = $value;

    # Verification de la compatibilite de la politique
    $tmp_value =~ s/\+/\\\+/;
    return ( 1, $value . $error_hash->{5} )
        if ( !grep( /^$tmp_value$/, @xmit_values_tab ) );

    if ( Lib_Network::get_if_status($bond) ) {
        $status_flag = 1;

        # L'interface doit etre down pour la modif
        ( $error, $error_msg ) = Lib_Network::ifdown($bond);
        return ( $error, $error_msg ) if ($error);
    }

    # Je set la politique
    ( $error, $error_msg ) = _set_opt( $bond, $XMIT_FILE, $value );

    if ($status_flag) {

        # Je relance l'interface
        my ( $tmp_error, $tmp_msg ) = Lib_Network::ifup($bond);
        if ($tmp_error) {
            return ( $tmp_error, $error_msg . ' + ' . $tmp_msg ) if ($error);
            return ( $tmp_error, $tmp_msg );
        }
    }
    return ( $error, $error_msg ) if ($error);

    return ( 0, '' );
}

# Fonction de verification de la validite d'un mode
# Cette fonction prend en param le mode (numerique ou texte)
# retourne (0,0) en cas de succes et un code d'erreur, un message
# d'erreur en cas d'echec
sub check_bond_mode {
    my ($mode) = @_;

    # Test si le mode est correct..
    if ( $mode =~ m/^\d*$/ ) {
        return ( 1, $error_hash->{3} ) if ( $mode < 0 || $mode > $#mode_tab );
    }
    else {
        return ( 1, $error_hash->{3} ) if ( !grep( /^$mode$/, @mode_tab ) );
    }
    return ( 0, 0 );
}

################### PRIVATES FUNCTIONS #####################

# Fonction de configuration d'une option dans un fichier
# param : nom du bond, le nom du fichier, le param a ajouter
sub _set_opt {
    my ( $bond, $option, $param ) = @_;

    my $file;

    $file = $SYS_PATH . $bond . '/bonding/' . $option;

    return ( _write_into_a_file( $file, $param ) );
}

# Fonction d'ajout d'une option dans un fichier
# param : nom du bond, le nom du fichier, le param a ajouter
sub _add_opt {
    my ( $bond, $option, $param ) = @_;

    my $file;
    my $to_add = $ACTION_ADD . $param;

    if ($bond) {
        $file = $SYS_PATH . $bond . '/bonding/' . $option;
    }
    else {
        $file = $SYS_PATH . $option;
    }

    return ( _write_into_a_file( $file, $to_add ) );
}

# Fonction de suppression d'une option dans un fichier.
# param : nom du bond, le nom du fichier, le param a ajouter
sub _del_opt {
    my ( $bond, $option, $param ) = @_;

    my $file;
    my $to_add = $ACTION_DEL . $param;

    if ($bond) {
        $file = $SYS_PATH . $bond . '/bonding/' . $option;
    }
    else {
        $file = $SYS_PATH . $option;
    }

    return ( _write_into_a_file( $file, $to_add ) );
}

# Fonction de recuperation de la liste des options dans
# un fichier
sub _get_opt {
    my ($file) = @_;
	my @return_tab;

    open( FILE, $file ) or return ( 1, $error_hash->{1} . $file );

    while (<FILE>) {
        my @tmp_tab;
        @tmp_tab = split( / /, $_ );
        chomp(@tmp_tab);
        push( @return_tab, grep( /\w/, @tmp_tab ) );
    }
    close(FILE);
    return ( 0, \@return_tab );
}

# Fonction d'ecriture dans un fichier.
sub _write_into_a_file {
    my ( $file, $param ) = @_;

    open( FILE, ">", $file ) or return ( 1, $error_hash->{1} . $file );

    syswrite( FILE, $param, length($param) );
    close(FILE);

    return ( 1, "Write error : " . $! ) if ($!);

    return ( 0, '' );
}

# Fonction de verification si l'interface passe en param est bien un bond
sub _verify_bond {
    my ($bond) = @_;
    my $return_tab;
    my $error_msg;

    ( $return_tab, $error_msg ) = _get_opt( $SYS_PATH . $BOND_MASTER_FILE );

    # Gestion de l'erreur
    return ( $return_tab, $error_msg ) if ( $return_tab == 0 );

    return ( 0, '' ) if ( grep( /^$bond$/, @{$return_tab} ) );

    return ( 1, $bond . $error_hash->{2} );
}

# Fonction d'ajout / suppression d'une interface.
sub _add_del_iface {
    my ( $bond, $action, $iface ) = @_;
    my $error;
    my $error_msg;

    if ( $action eq $ACTION_ADD ) {

        # ifdown l'interface cree un bug.. je laisse le code
        # au cas ou.. correction du bug #281
        # 	# L'interface doit etre down pour l'ajout
        ($error, $error_msg) = Lib_Network::ifdown($iface);
        return ($error, $error_msg) if ($error);

        ( $error, $error_msg ) = _add_opt( $bond, $SLAVE_FILE, $iface );
    }
    else {
        ( $error, $error_msg ) = _del_opt( $bond, $SLAVE_FILE, $iface );
    }

    return ( $error, $error_msg ) if ($error);

    return ( 0, '' );
}

1;
