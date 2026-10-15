// Accueil de YouTube Music (France, non connecté) relevé le 15/10/2026 sur music.youtube.com :
// mêmes étagères, même ordre, mêmes playlists, sous-titres et pochettes.
// Les playlists et albums sont lus sans clé par le lecteur intégré officiel.

export interface ElementAccueil {
  id: string;            // id de playlist (RDCLAK…, PL…, OLAK… pour les albums)
  nom: string;
  sousTitre: string;
  pochette: string | null;
}

export type EtagereAccueil =
  | { type: 'playlists'; surtitre?: string; titre: string; elements: ElementAccueil[] }
  | { type: 'titres'; surtitre?: string; titre: string; idsVideos: string[] };

const P = (taille: string) => (id: string) => `https://yt3.googleusercontent.com/${id}=${taille}`;
const pochette = P('w544-h544-l90-rj');

export const ACCUEIL: EtagereAccueil[] = [
  {
    type: 'playlists',
    surtitre: 'Les titres les plus populaires du moment sont réunis ici',
    titre: 'Hits incontournables',
    elements: [
      { id: 'RDCLAK5uy_lBNUteBRencHzKelu5iDHwLF6mYqjL-JU', nom: 'Pop Certified', sousTitre: 'Olivia Rodrigo, Sabrina Carpenter, Bruno Mars et Taylor Swift', pochette: pochette('H-a23V_iN1LA7Vi8r8H5grE9FmjUTIsy_WjzUO_5hYxNT4TRZNkBXSFKlNHLab3kKYpBlsqqhcCuhWE') },
      { id: 'RDCLAK5uy_mCvOm3kQy1RTBwDOGYkNhtHwMO89ffquk', nom: 'Crème French Pop', sousTitre: 'Louane, Marine, Joseph Kamel et Pierre de Maere', pochette: pochette('jle51C_go64AgpuuYYpM7pDOJ6AZe-bQMMK98eWc39hdeLH8XdVlCJkL9EjiWKqKzy09ANFVne8aTNk') },
      { id: 'RDCLAK5uy_ly6s4irLuZAcjEDwJmqcA_UtSipMyGgbQ', nom: 'La Hit List', sousTitre: 'Mauvais Djo, GIMS, David Guetta et KeBlack', pochette: pochette('sX3HeToDY5U5LaaGlEUEpPN8Qqt5Zc7pQEqba85n9kFj3q2KwSkETbfuzU5Nco5n3tDDymZGWKsfzg') },
      { id: 'RDCLAK5uy_lMgwoUFBJgUMlCgT3F3wqXZ62CY0RwUMU', nom: 'Hotlist Variété française', sousTitre: 'Christophe Maé, Pascal Obispo, Grand Corps Malade et Gauvain Sers', pochette: pochette('rkdpBdR2wtUu06qG3gq3JCX8krOVAm2q-E60xSf2mT10s1DWv_Oh1khTEEcs-KrVDDjpMq_7NTIdXIA') },
      { id: 'RDCLAK5uy_mu-BhJj3yO1OXEMzahs_aJVtNWJwAwFEE', nom: 'Highline R&B', sousTitre: 'Leon Thomas, Chris Brown, Kehlani et kwn', pochette: null },
      { id: 'RDCLAK5uy_m5CnuDgYzjtZXfo58-6jqX5GRSFKWp5gM', nom: 'Hashtag Hits', sousTitre: 'Nouvelle École, Post Malone, Dayarga et Nayte', pochette: null },
      { id: 'RDCLAK5uy_kAzvNwVxyZqDv4RypgYluniT5Or7V1rUU', nom: 'On Fleek Pop Urbaine', sousTitre: 'Mauvais Djo, Aya Nakamura, KeBlack et Meryl', pochette: null },
      { id: 'RDCLAK5uy_ktdI-meQ69P3xi5j3twLqwA0WhAGbEs90', nom: 'Le Drop', sousTitre: 'David Guetta, HUGEL, The Chainsmokers et Alesso', pochette: null },
      { id: 'RDCLAK5uy_lBGRuQnsG37Akr1CY4SxL0VWFbPrbO4gs', nom: 'Tubes hip-hop du moment', sousTitre: 'Drake, Don Toliver, Fatt Smaxk et J. Cole', pochette: null },
      { id: 'RDCLAK5uy_mK9RSAOLuO3PT_u74S1YJzlUneNOgTUTE', nom: 'Rap Podium', sousTitre: 'Ninho, La Rvfleuze, Tiakola et Lagui', pochette: null },
    ],
  },
  {
    type: 'playlists',
    surtitre: 'Les plus grands hits de tous les temps !',
    titre: '100% hits',
    elements: [
      { id: 'RDCLAK5uy_lMzHW51iFg1Kx0d_2EHpzbOgCrwtu8cgI', nom: 'Les plus grands succès des années 1980', sousTitre: 'Michael Jackson, Prince & The Revolution, Madonna et U2', pochette: pochette('VGxWK75H8M5k3r2I89b7Tg9Mi1JPNkCtc9IOkAfpznmJu4N7toBj_PB2Fubc_sFHa8CZ1MqSb6AqVTE') },
      { id: 'RDCLAK5uy_nwmU7GOH9bo9N3RB566bAfjrMTZHJ6AhY', nom: 'Classiques du rap français', sousTitre: "Suprême NTM, Shurik'n, Rohff et IAM", pochette: pochette('EeemjaOQHV6ikTLNOLUWugb8ejVtn9R3pvLHewscPExJi0KqFkH3-ZqmcDj6QL1RYg20fCId_e8ZFOI') },
      { id: 'RDCLAK5uy_lpMyvmlj27JH-NuH9pysxqZeg5PJQNPmw', nom: 'Hits 2000', sousTitre: 'Fatal Bazooka, Lorie, Christophe Maé et Nâdiya', pochette: pochette('6CkjVAzLVxT2ETY9jO3RrjfOgAnFhKOb0Bx53C6F3fJCOFXLY034xQJw1pTOgsU53e2brxsrv2fpCgE') },
      { id: 'RDCLAK5uy_nkiTFoMVcVE0v8LuzpEcfjHH0WLFhDF1I', nom: 'Hits 10', sousTitre: 'Soprano, Stromae, GIMS et Kendji Girac', pochette: pochette('z85SeOkyJVCRccNq6s1lkbIcSfLZPk-bbjg5OIOcRu2jSjhelE4aWOrVdDHUHYiWQ3aMlUvd9vr5LA') },
      { id: 'RDCLAK5uy_ncNOYjq7OOSZeazddJXSe-s9wXgjTG5uw', nom: 'Les hits du Rap Français', sousTitre: 'GIMS, Gazo, SDM et JuL', pochette: null },
      { id: 'RDCLAK5uy_nWufZ3-rH924TsgmroKWiilEk-BQweReI', nom: 'Hits 80', sousTitre: 'Telephone, Jean-Jacques Goldman, Julien Clerc et Renaud', pochette: null },
      { id: 'RDCLAK5uy_kP2172rQNb3KFXz880xp6M98R_ME5CIKA', nom: 'Hip-Hop Classics', sousTitre: 'JAY-Z, The Notorious B.I.G., Dr. Dre et Eminem', pochette: null },
      { id: 'RDCLAK5uy_mhri0dZDOPMOmDRxoIPN_9Z0bwutZZVe8', nom: 'Hits 90', sousTitre: 'Jean-Jacques Goldman, Suprême NTM, Doc Gyneco et Alliance Ethnik', pochette: null },
      { id: 'RDCLAK5uy_mn6mX0GYERCgJxFbmlSXE8Vxqhafy1VoY', nom: 'Culture tubes', sousTitre: 'Claude François, Jean-Jacques Goldman, France Gall et Daniel Balavoine', pochette: null },
      { id: 'RDCLAK5uy_lDceTtVda9FDfCnqwyTDf80KhyUJlEtdM', nom: 'Hits 70', sousTitre: 'Claude François, Michel Sardou, Johnny Hallyday et Michel Polnareff', pochette: null },
    ],
  },
  {
    type: 'playlists',
    titre: 'Playlists de la communauté populaires',
    elements: [
      { id: 'PLCyVw7TMSAuMccwud2l97aFyD8lndXrYO', nom: '2024. Les 50 meilleurs Titres du moment en France. Tubes pop', sousTitre: 'Best of Top Hits France • 4,3 M de vues', pochette: 'https://yt3.googleusercontent.com/IF9U6y00iFHPoL6fL3Mqwgfd4kjdYBN2xFlXFp6bktx-jQSjpg8GTEIBnGcuumYDkgAQvnHU5YOi=s576' },
      { id: 'PLSvTxsFVnYWJlnK-3NKh22qNFDvX1NtWB', nom: 'année 90 2000', sousTitre: 'Cindy • 2,5 M de vues', pochette: 'https://yt3.ggpht.com/0olGa4HVvt2PszsGmmXFHAkJTOVXiw1AGn2UErIBqTVIb_16Yg_XxZXQGnd4jje8YZ-kCM1emg=s576' },
      { id: 'PL4x3LF4828OrzWI6kv2jakruvYDoKzATU', nom: 'Chansons française 80-90', sousTitre: 'Camille Bonzon • 12 M de vues', pochette: 'https://yt3.googleusercontent.com/Mk23kPrSMm8GqXg2O_2dJWCOmoqmdlYHhV2Ve7LJlIYQcRGmyVTwNYsOk11K23IMi7IETY4ZUD0=s576' },
      { id: 'PLrYIoSaX0phjpuVIfVGy9XtBnqgCfc1bm', nom: 'Musique soirée', sousTitre: 'Romane Bioteau • 8 M de vues', pochette: 'https://yt3.ggpht.com/_WCNZAlYs7Yj-Uk1_Mh0Jje2xYUuQF0MNKa22X98VSfoExQXgvXrphDSgtE4_bJ0Qysbaj0i_h0=s576' },
      { id: 'PLkvHXL6im1LIHbB1RJLmHLjl7Xat7U_lp', nom: 'Années 80 français', sousTitre: 'Regine Spiegler • 1,3 M de vues', pochette: null },
      { id: 'PLmCtPqZDYBzzbR1qUA6kYD_u2soaLK3pi', nom: 'boite de nuit shatta 2025', sousTitre: 'Mathyss_tennis • 2,5 M de vues', pochette: null },
    ],
  },
  {
    type: 'playlists',
    surtitre: 'Les découvertes de la semaine',
    titre: 'Nouveaux sons',
    elements: [
      { id: 'RDCLAK5uy_mztvVkPbbOgYQFQUOi9VbLcZ4ewdmBczw', nom: 'RELEASED', sousTitre: 'girl in red, Kid Francescoli et L2B', pochette: null },
      { id: 'RDCLAK5uy_md0A3ePq95xyweK-V-jfXFce8QEmXLhu8', nom: 'Jeunes Espoirs', sousTitre: 'TeddyBear, Jeanne, Léa Doffey et Nuit Incolore', pochette: null },
      { id: 'RDCLAK5uy_mfdY-wgukpeBhEvTg6BPW_WgcUKX7rXaA', nom: 'Nouveaux sons Rap', sousTitre: 'Tiakola, COLORS, SDM et Leto', pochette: null },
      { id: 'RDCLAK5uy_ll67QNQ4bbLx_AhpkeWe3tzSq4b0X5-6U', nom: 'Afro vibes', sousTitre: 'Fally Ipupa, Didi B, Mauvais Djo et Tiakola', pochette: null },
      { id: 'RDCLAK5uy_kT4N8v_Q_Q3eFXmkdTMUWDlVlgrnLnmxE', nom: 'Futurs Hits', sousTitre: 'Tiakola, Taylor Swift, Angèle et Ridsa', pochette: null },
      { id: 'RDCLAK5uy_nOwL35BM_GUTEbdbw_9FmvQhPWWdd3sAg', nom: 'Pop Fresh', sousTitre: 'Rachel Chinouriri, XO, Olivia C. Dacal et Kim Petras', pochette: null },
      { id: 'RDCLAK5uy_mR3VE_wMgQT1A6F4XmBGdBq2rxuvfKJ4k', nom: 'Nouveautés indie françaises', sousTitre: 'Baptiste Sartoria, Odezenne, MDNS et Dynamite Shakers', pochette: null },
      { id: 'RDCLAK5uy_km2BIHK1LQuxwlRO5DIV1C-M7z-ZmMn9w', nom: 'Fraîcheur urbaine', sousTitre: 'Mauvais Djo, Tiakola, Tayc et DJ Kawest', pochette: null },
      { id: 'RDCLAK5uy_n8xRDDZKf5vOGK0qLOhvgb4I8oDzk0CWA', nom: 'Rap : la relève', sousTitre: 'Nouvelle École, ANS, Tookie2Beriz et Beendo Z', pochette: null },
      { id: 'RDCLAK5uy_k0RPAZDb4p0DEIY5DKIR3vdKSGHSdIPM8', nom: 'Rap du Maghreb', sousTitre: 'Didine Canon 16, Stormy, ElGrandeToto et Bo9al', pochette: null },
    ],
  },
  {
    type: 'titres',
    titre: 'Sélection rapide',
    idsVideos: ['mOUdsRP41qY', 'Ntx-MGr-7TY', 'ZMGNAvNs_20', 'LR_pYM4B6EU', 'd0bfslVN97w', 'ljAH6jNaApU', 'n0GXk_T2zs8', 'E8glAzvbP4Q', 'SXoQHp2cQQc', 'nmeEy0pkaK4', 'IO_GLvVB5Vc', 'RqymFLjriPc'],
  },
  {
    type: 'playlists',
    titre: 'Nouveautés',
    elements: [
      { id: 'OLAK5uy_mWWxzh1zbtzbC2KJgTUV_tphdxmV3e0qw', nom: 'Jeune Demoiselle', sousTitre: 'Single • Manon Lisa', pochette: pochette('vbezyiOe7xmPOpSnIe-XLUUO18kGNgPed1f85Z5IQV0ox3vOL_wMQpsnT9m8M-cZ5OOu3WvP9Rm6nSVlXg') },
      { id: 'OLAK5uy_nQpCsff6FN8Ayz6pnVsG6OD0q5lRGNvaY', nom: 'Blanco nemesis', sousTitre: 'Album • Booba', pochette: pochette('fadnaJEG5oDsowajFHkYquW2vSb-KHN4e5t8ccLSoVCr4s91SY7WEiXEM3QYEU8cDDB-7OVjw7xIFbNL1A') },
      { id: 'OLAK5uy_m7jqqbE6yMyXDz7q6tCmt0GNEe0pwfYPk', nom: 'Que toi', sousTitre: 'Single • Fanny J', pochette: pochette('UiTvR3tF_G5-l-AnH7JdksV5ZkU73-vORtfMV6RitcjraOj66OlzeSURJiIkzKVHMQkHVRfNtrSbIbKLOw') },
      { id: 'OLAK5uy_nI_wsPcT-uiy0M3XwFFhDG_irFGuLegBk', nom: 'TONIGHT', sousTitre: 'Album • TKS 2G', pochette: pochette('vJHeYiUAbY4xW196U0uWnJhgGDyDCFwvdi6oGlBGI_GYUAorLCUJHxUnVNcXXBP6L4elQ7jI3Lif8uEP') },
      { id: 'OLAK5uy_nSUL1zFwcA9RN1gaQaFhy6L5xdtn0eTx4', nom: 'Effets Secondaires', sousTitre: 'Album • Lisa Pariente', pochette: null },
      { id: 'OLAK5uy_nvhgkSZWeb41zdHLsphw-1qiCm3wyF5T0', nom: 'Te conocí', sousTitre: 'Single • Zenar et Nicky Jam', pochette: null },
      { id: 'OLAK5uy_khIV_vKdqjVqvrrAJjy3YbCR-iIRq3rDA', nom: '1987 (Live à Paris / 2026)', sousTitre: 'Single • Calogero', pochette: null },
      { id: 'OLAK5uy_l-W-5KpDyO38QJ550MZvSQmFfUpwMSFUo', nom: 'PITCOIN', sousTitre: 'Album • Pitbull', pochette: null },
      { id: 'OLAK5uy_l9NhAGbTiMKIUTBNTO1N49aQrdOtp43k8', nom: 'I Kissed A Girl x Sam Sulek', sousTitre: 'Album • Luke Muzzic', pochette: null },
      { id: 'OLAK5uy_mZwQVKZolwEuC3MjqlfAVPfVJJcEqoyk8', nom: "C'est tout moi", sousTitre: 'Single • Adèle Castillon', pochette: null },
    ],
  },
];
