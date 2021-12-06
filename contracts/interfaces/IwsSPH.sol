// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.7.5;

import "./IERC20.sol";

// Old wsSPH interface
interface IwsSPH is IERC20 {
  function wrap(uint256 _amount) external returns (uint256);

  function unwrap(uint256 _amount) external returns (uint256);

  function wSPHTosSPH(uint256 _amount) external view returns (uint256);

  function sSPHTowSPH(uint256 _amount) external view returns (uint256);
}
