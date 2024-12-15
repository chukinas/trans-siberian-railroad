defmodule TsrWeb.MapLayout.LandmassCoords do
  @moduledoc """
  Coordinates of the outline of the Russian landmass.
  """

  defp get(scale) do
    raw()
    |> Stream.map(&String.to_integer/1)
    |> Stream.map(&round(&1 * scale))
    |> Enum.chunk_every(2)
    |> Enum.uniq()
  end

  def coords(scale) do
    get(scale) |> List.flatten() |> Enum.join(" ")
  end

  def viewbox(scale) do
    coords = get(scale)
    padding = 1
    {x_min, x_max} = coords |> Stream.map(&Enum.at(&1, 0)) |> Enum.min_max()
    {y_min, y_max} = coords |> Stream.map(&Enum.at(&1, 1)) |> Enum.min_max()

    [
      x_min - padding,
      y_min - padding,
      x_max - x_min + 2 * padding,
      y_max - y_min + 2 * padding
    ]
    |> Enum.join(" ")
  end

  defp raw() do
    ~w(
  3225 861 3203 897 3216 927 3199 937 3207 964 3201 973 3216 994 3195 1024 3201 1060 3219 1092 3222 1133 3219 1174 3231 1197 3263 1223 3281 1253 3317 1270 3359 1282 3411 1281 3454 1250 3489 1220 3510 1178 3530 1117 3527 1055 3544 1016 3562 972 3564 923 3570 874 3567 828 3561 790 3568 756 3543 733 3564 708 3582 684 3603 687 3598 638 3565 593 3522 550 3465 543 3409 523 3355 520 3313 558 3299 599 3268 629 3259 671 3207 659 3151 658 3108 686 3071 725 3031 765 2990 797 2970 783 2953 781 2942 797 2907 790 2894 819 2859 816 2835 865 2814 862 2779 917 2747 935 2710 917 2688 946 2683 992 2657 1012 2619 1065 2576 1063 2526 1073 2486 1059 2416 1057 2366 1038 2352 1061 2340 1060 2346 1031 2286 999 2221 977 2207 988 2237 1032 2199 1039 2194 1077 2151 1083 2103 1073 2094 1047 2066 1072 1999 1075 1964 1090 1929 1117 1890 1112 1880 1143 1866 1172 1843 1178 1832 1133 1784 1127 1779 1164 1761 1194 1727 1199 1663 1260 1605 1302 1601 1354 1623 1385 1634 1452 1625 1522 1607 1563 1566 1577 1551 1598 1530 1600 1500 1645 1465 1700 1437 1747 1428 1800 1400 1848 1347 1844 1328 1800 1300 1800 1263 1834 1208 1866 1200 1918 1248 1917 1274 1967 1278 2030 1273 2085 1253 2123 1202 2119 1196 2174 1209 2232 1181 2281 1147 2321 1151 2372 1161 2420 1201 2453 1229 2501 1227 2564 1221 2642 1234 2691 1234 2742 1241 2784 1204 2814 1183 2796 1161 2807 1170 2840 1130 2839 1121 2863 1075 2884 1013 2855 976 2839 904 2828 867 2858 896 2903 936 2916 927 2950 876 2939 835 2911 794 2889 761 2914 775 2983 751 2979 726 2945 655 2943 630 2976 588 2907 566 2913 562 2986 551 3055 558 3120 562 3181 561 3252 546 3315 543 3378 599 3406 609 3442 603 3479 635 3520 670 3575 688 3626 695 3690 716 3767 695 3789 708 3820 762 3831 767 3866 790 3872 809 3923 812 3981 781 3992 805 4065 825 4130 827 4178 812 4220 818 4262 860 4281 876 4259 938 4262 955 4209 964 4152 985 4102 1001 4055 1019 4010 1060 3988 1085 3942 1102 3885 1112 3837 1140 3815 1192 3808 1236 3790 1270 3777 1276 3800 1337 3795 1340 3813 1417 3785 1435 3732 1476 3748 1491 3705 1482 3660 1509 3633 1512 3588 1494 3536 1456 3508 1481 3445 1496 3370 1544 3349 1590 3347 1612 3300 1669 3263 1748 3227 1777 3240 1750 3291 1739 3355 1790 3385 1824 3342 1855 3292 1886 3319 1916 3321 1928 3298 1965 3304 1973 3327 2026 3329 2081 3329 2126 3352 2146 3399 2184 3402 2185 3448 2209 3487 2249 3522 2228 3548 2249 3590 2250 3637 2225 3683 2234 3689 2271 3646 2295 3684 2295 3721 2332 3768 2377 3752 2417 3766 2455 3802 2504 3834 2534 3844 2557 3882 2544 3908 2554 3957 2582 4008 2607 4016 2614 3996 2640 4002 2690 4030 2744 4048 2784 4023 2762 3980 2733 3935 2717 3872 2754 3841 2796 3849 2845 3845 2838 3800 2867 3776 2913 3783 2953 3828 2973 3821 2944 3771 2934 3732 2972 3733 2956 3702 2978 3682 2977 3652 3008 3658 3032 3694 3061 3700 3083 3745 3114 3731 3156 3743 3191 3775 3225 3769 3266 3793 3305 3817 3319 3793 3357 3808 3393 3808 3450 3834 3531 3851 3572 3872 3583 3852 3643 3855 3698 3879 3711 3931 3779 3934 3769 3988 3769 4041 3720 4079 3718 4104 3751 4126 3788 4130 3809 4115 3828 4156 3896 4215 3897 4236 3869 4238 3851 4281 3901 4283 3933 4312 3963 4287 4040 4284 4087 4283 4121 4266 4170 4275 4164 4305 4131 4313 4141 4373 4162 4429 4188 4427 4198 4566 4238 4723 4228 4840 4238 4891 4269 4880 4297 4841 4338 4856 4365 4911 4418 4961 4482 4966 4531 4972 4573 5007 4597 5049 4599 5103 4651 5135 4656 5207 4729 5243 4800 5205 4811 5214 4796 5257 4806 5298 4830 5340 4900 5334 4943 5298 4952 5315 5002 5312 5055 5301 5060 5274 5095 5257 5148 5242 5200 5220 5246 5222 5265 5192 5329 5191 5354 5180 5369 5206 5398 5206 5420 5236 5471 5240 5503 5251 5530 5274 5527 5317 5577 5348 5631 5364 5651 5343 5686 5369 5734 5382 5778 5407 5826 5381 5888 5358 5890 5327 5862 5287 5875 5256 5852 5218 5871 5178 5928 5135 5933 5094 5964 5063 5989 5088 6013 5116 6037 5113 6063 5142 6108 5143 6149 5170 6168 5173 6180 5194 6239 5193 6267 5213 6251 5248 6262 5298 6290 5310 6316 5363 6363 5371 6379 5397 6442 5395 6474 5373 6553 5361 6574 5340 6649 5371 6727 5382 6803 5426 6799 5456 6849 5496 6921 5506 7003 5526 7021 5513 7072 5519 7129 5489 7181 5488 7228 5441 7275 5440 7309 5413 7304 5367 7382 5312 7405 5325 7429 5308 7475 5316 7485 5336 7532 5354 7570 5325 7634 5333 7724 5372 7760 5358 7805 5298 7863 5275 7859 5205 7869 5102 7892 5012 7923 4999 7921 4941 7905 4883 7861 4892 7848 4865 7877 4814 7926 4757 7969 4762 7981 4728 8084 4703 8105 4671 8154 4667 8179 4692 8260 4704 8278 4679 8329 4693 8335 4719 8363 4719 8375 4748 8403 4763 8422 4797 8442 4801 8450 4838 8484 4852 8483 4889 8518 4912 8542 4945 8587 5020 8622 5045 8628 5087 8681 5125 8738 5100 8765 5125 8796 5120 8845 5097 8893 5136 8938 5144 8970 5167 9015 5244 9054 5274 9165 5249 9188 5202 9227 5132 9271 5103 9307 5056 9358 5063 9390 5169 9366 5210 9370 5335 9398 5360 9385 5418 9385 5477 9360 5522 9388 5542 9374 5580 9267 5583 9245 5601 9238 5639 9192 5667 9227 5752 9263 5788 9264 5851 9309 5875 9390 5858 9427 5885 9513 5881 9534 5853 9567 5846 9577 5803 9641 5733 9650 5687 9687 5617 9655 5583 9681 5564 9706 5513 9711 5469 9695 5449 9735 5345 9778 5270 9767 5174 9766 5089 9787 5003 9776 4934 9801 4884 9791 4842 9811 4807 9813 4776 9797 4742 9778 4695 9771 4621 9733 4582 9733 4552 9695 4483 9671 4426 9680 4387 9668 4338 9639 4298 9623 4242 9617 4206 9585 4175 9589 4129 9559 4105 9521 4095 9501 4079 9469 4076 9454 4061 9406 4061 9392 4047 9370 4046 9308 4088 9332 4156 9332 4211 9306 4165 9298 4158 9276 4231 9243 4179 9219 4169 9226 4154 9203 4138 9186 4168 9201 4190 9189 4228 9161 4196 9156 4164 9117 4124 9038 4168 9000 4141 9017 4114 9015 4076 9040 4054 9038 4022 9055 3994 9084 3950 9078 3917 9100 3857 9087 3797 9107 3759 9116 3696 9149 3631 9138 3597 9157 3555 9150 3502 9160 3462 9178 3416 9184 3365 9196 3310 9225 3265 9266 3223 9314 3188 9362 3167 9376 3137 9419 3145 9438 3131 9425 3108 9451 3092 9508 3090 9522 3036 9563 3035 9575 2992 9561 2977 9574 2933 9612 2920 9669 2914 9693 2868 9716 2864 9742 2883 9771 2863 9783 2876 9733 2931 9758 2950 9778 2949 9823 2889 9842 2851 9846 2795 9864 2800 9890 2782 9914 2750 9909 2710 9866 2736 9829 2712 9820 2665 9803 2619 9810 2573 9815 2522 9800 2471 9798 2416 9777 2401 9770 2374 9789 2348 9782 2319 9810 2301 9815 2264 9856 2244 9855 2219 9891 2230 9904 2212 9905 2176 9924 2183 9940 2223 9965 2267 10002 2237 10036 2194 10033 2152 10011 2093 9990 2010 9959 1957 9953 1925 9967 1894 9991 1867 10026 1854 10041 1868 10018 1894 10022 1949 10060 1997 10100 2042 10116 2090 10145 2150 10151 2193 10196 2257 10223 2344 10209 2398 10200 2447 10199 2472 10192 2494 10225 2560 10217 2629 10227 2696 10197 2767 10183 2838 10235 2892 10280 2974 10300 3051 10325 3094 10399 3144 10475 3216 10531 3285 10571 3326 10594 3277 10597 3200 10581 3144 10588 3093 10588 3048 10565 2984 10591 2919 10576 2845 10587 2791 10589 2749 10572 2686 10576 2630 10581 2572 10570 2518 10542 2500 10526 2431 10484 2414 10460 2447 10469 2470 10461 2490 10423 2495 10403 2449 10370 2409 10360 2356 10335 2303 10305 2251 10292 2191 10299 2148 10342 2046 10355 1963 10386 1892 10407 1837 10433 1833 10446 1788 10525 1804 10545 1779 10510 1743 10497 1682 10486 1619 10488 1564 10466 1550 10452 1503 10437 1429 10440 1372 10441 1294 10435 1245 10422 1190 10442 1143 10474 1095 10506 1062 10487 1035 10451 995 10404 950 10344 922 10295 943 10262 976 10212 981 10206 1007 10172 1004 10174 955 10182 927 10158 848 10135 807 10103 771 10065 772 10023 744 9988 712 10001 698 10003 666 10039 704 10087 703 10100 722 10120 719 10130 682 10116 627 10151 615 10173 585 10237 599 10307 567 10315 495 10260 455 10319 412 10261 358 10156 379 10016 356 9880 366 9778 340 9691 420 9762 487 9626 537 9573 574 9529 610 9489 653 9443 682 9393 717 9370 765 9343 820 9306 867 9312 925 9344 975 9394 1002 9419 1043 9382 1080 9361 1072 9303 1099 9242 1136 9192 1181 9151 1226 9109 1235 9092 1287 9077 1307 9068 1347 9040 1381 8996 1389 8945 1382 8922 1330 8865 1320 8814 1340 8738 1382 8688 1416 8646 1468 8608 1541 8577 1549 8545 1527 8484 1502 8410 1499 8335 1511 8272 1534 8198 1575 8126 1593 8057 1622 8035 1652 8037 1684 8009 1667 7997 1683 8021 1726 8040 1790 8073 1801 8095 1822 8070 1838 8024 1821 7990 1860 8023 1895 8011 1905 7956 1880 7902 1893 7878 1928 7869 1971 7825 1961 7790 1945 7769 1921 7751 1934 7755 1979 7759 2033 7784 2079 7772 2100 7735 2092 7692 2097 7659 2069 7637 2029 7615 1999 7584 2001 7577 1983 7606 1951 7595 1914 7572 1873 7545 1833 7516 1799 7469 1790 7428 1792 7391 1808 7350 1793 7308 1784 7298 1822 7278 1847 7314 1886 7312 1924 7282 1914 7270 1914 7257 1935 7219 1925 7178 1928 7130 1926 7112 1885 7092 1874 7037 1874 6985 1878 6942 1887 6919 1903 6879 1896 6851 1872 6839 1875 6836 1902 6795 1896 6762 1909 6723 1941 6685 1970 6640 1991 6601 2007 6570 1993 6586 1957 6619 1927 6637 1933 6670 1890 6701 1854 6717 1809 6743 1786 6764 1792 6815 1756 6833 1713 6857 1676 6857 1646 6823 1621 6861 1594 6829 1552 6790 1514 6768 1472 6719 1461 6674 1475 6624 1482 6610 1504 6582 1493 6595 1451 6567 1447 6507 1430 6527 1392 6535 1366 6510 1354 6467 1357 6428 1380 6393 1413 6381 1454 6395 1491 6356 1512 6310 1509 6325 1556 6295 1537 6255 1562 6199 1562 6222 1523 6200 1514 6138 1538 6096 1544 6090 1572 6047 1575 6006 1592 5993 1579 5958 1587 5938 1596 5911 1597 5889 1629 5871 1632 5851 1621 5832 1624 5825 1655 5808 1652 5801 1670 5788 1651 5769 1661 5772 1675 5750 1681 5747 1693 5790 1688 5795 1712 5771 1712 5780 1729 5781 1745 5807 1771 5791 1785 5750 1779 5721 1789 5706 1776 5683 1777 5641 1782 5599 1776 5554 1768 5510 1755 5484 1775 5472 1813 5465 1850 5465 1894 5477 1937 5503 1965 5489 1993 5456 2002 5430 1977 5408 1933 5384 1891 5344 1889 5330 1873 5346 1854 5330 1831 5306 1849 5314 1887 5297 1901 5321 1924 5293 1935 5260 1919 5242 1886 5219 1895 5219 1936 5231 1982 5265 2022 5254 2060 5227 2054 5202 1999 5146 1954 5154 1917 5185 1877 5225 1850 5247 1801 5242 1747 5226 1731 5216 1776 5202 1814 5167 1846 5121 1853 5084 1878 5067 1917 5067 1961 5050 1990 5055 2024 5047 2040 5015 2063 4998 2099 4979 2106 4967 2132 4961 2173 4934 2209 4942 2227 4981 2244 5034 2238 5055 2255 5071 2294 5103 2335 5089 2356 5090 2393 5073 2429 5047 2437 5020 2474 5043 2499 5075 2516 5082 2544 5071 2552 5047 2528 5001 2512 4997 2483 5004 2430 5044 2384 5041 2314 5019 2289 4947 2277 4915 2304 4904 2371 4875 2412 4840 2426 4818 2456 4801 2456 4786 2498 4748 2501 4710 2507 4676 2516 4650 2542 4624 2542 4603 2516 4568 2500 4536 2476 4531 2424 4575 2432 4579 2457 4617 2457 4656 2454 4668 2431 4695 2434 4711 2402 4732 2407 4756 2379 4807 2356 4833 2311 4868 2281 4876 2255 4855 2219 4853 2185 4885 2170 4898 2135 4928 2107 4931 2073 4956 2032 4990 2008 5010 1969 5026 1922 5015 1896 5014 1863 5050 1824 5092 1790 5116 1755 5139 1721 5116 1691 5075 1653 5036 1629 4989 1655 4949 1685 4920 1729 4862 1754 4796 1770 4752 1812 4753 1827 4775 1833 4779 1847 4740 1880 4714 1923 4685 1919 4670 1946 4661 1980 4686 1997 4702 2025 4676 2054 4677 2090 4691 2134 4641 2179 4623 2179 4593 2112 4606 2084 4574 2020 4576 1997 4552 1953 4542 1912 4527 1906 4537 1884 4512 1833 4474 1806 4440 1767 4408 1762 4375 1768 4371 1805 4347 1820 4349 1848 4278 1851 4260 1876 4243 1864 4272 1828 4279 1795 4241 1780 4200 1769 4178 1785 4162 1780 4137 1729 4102 1717 4064 1715 4037 1747 4022 1745 4022 1707 4007 1701 4004 1673 4034 1675 4048 1645 4075 1628 4068 1609 4009 1600 3993 1620 3974 1618 3953 1584 3912 1560 3866 1558 3823 1549 3780 1523 3766 1527 3757 1561 3743 1560 3723 1527 3704 1523 3667 1555 3623 1561 3603 1548 3575 1517 3567 1469 3583 1424 3612 1402 3651 1399 3704 1437 3726 1431 3732 1381 3756 1343 3740 1294 3726 1241 3703 1243 3691 1274 3663 1308 3627 1326 3586 1349 3544 1366 3535 1406 3499 1443 3454 1448 3411 1479 3404 1455 3409 1421 3401 1372 3387 1356 3351 1356 3309 1348 3277 1324 3256 1334 3237 1330 3217 1312 3152 1334 3112 1415 3089 1395 3065 1398 3055 1355 3066 1290 3063 1244 3075 1206 3057 1199 3042 1211 3025 1195 2995 1197 2998 1234 2983 1271 2977 1318 2962 1324 2949 1352 2931 1358 2918 1339 2901 1330 2897 1284 2895 1230 2914 1173 2950 1131 2998 1094 3019 1049 3066 1048 3110 1024 3130 977 3146 926 3174 889 3202 856
  )
  end
end